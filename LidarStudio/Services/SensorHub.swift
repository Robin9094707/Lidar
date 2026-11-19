import ARKit
import CoreLocation
import CoreMotion
import SwiftUI

// MARK: - Modelle

enum PlaceKind: String, Codable {
    case indoor, outdoor, unknown

    var title: String {
        switch self {
        case .indoor: "Drinnen"
        case .outdoor: "Draußen"
        case .unknown: "Unklar"
        }
    }

    var icon: String {
        switch self {
        case .indoor: "building.2.fill"
        case .outdoor: "sun.max.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .indoor: Theme.accent
        case .outdoor: Theme.yellow
        case .unknown: .gray
        }
    }
}

enum PlaceOverride: String, CaseIterable, Identifiable {
    case auto, indoor, outdoor
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "Automatisch"
        case .indoor: "Drinnen"
        case .outdoor: "Draußen"
        }
    }
}

struct Evidence: Identifiable, Hashable {
    var id: String { text }
    let text: String
    let icon: String
    /// > 0 spricht für drinnen, < 0 für draußen
    let weight: Double
}

struct PlaceAssessment {
    let place: PlaceKind
    let confidence: Double
    let evidence: [Evidence]
}

struct FloorCalibration: Codable, Equatable {
    var floor: Int
    var pressureKPa: Double
    var absoluteAltitude: Double?
    var date: Date
    var automatic: Bool
}

struct FloorEstimate {
    let floor: Int?
    let source: String
    let heightAboveReference: Double?
    let warning: String?
}

/// Sensordaten zum Zeitpunkt einer Aufnahme (wird mit jedem Scan gespeichert).
struct EnvironmentSnapshot: Codable, Hashable {
    var latitude: Double?
    var longitude: Double?
    var horizontalAccuracy: Double?
    var altitude: Double?
    var pressureKPa: Double?
    var floor: Int?
    var floorSource: String?
    var place: PlaceKind
    var placeConfidence: Double
    var heading: Double?
    var roomHeight: Float?
}

enum FloorName {
    static func name(_ floor: Int) -> String {
        switch floor {
        case 0: "Erdgeschoss"
        case 1...: "\(floor). Obergeschoss"
        default: "\(-floor). Untergeschoss"
        }
    }

    static func short(_ floor: Int) -> String {
        switch floor {
        case 0: "EG"
        case 1...: "\(floor). OG"
        default: "\(-floor). UG"
        }
    }
}

// MARK: - SensorHub

/// Bündelt alle Sensoren des Geräts: GPS, Kompass, Barometer, Höhenmesser,
/// Schrittzähler/Stockwerkzähler, Bewegungserkennung, Gyroskop/Beschleunigung,
/// Magnetometer sowie LiDAR- und Lichtdaten aus ARKit. Sensoren laufen nur,
/// solange sie gebraucht werden (Referenzzählung), und werden bei Hitze oder
/// Stromsparmodus gedrosselt.
@MainActor
@Observable
final class SensorHub {
    static let shared = SensorHub()

    // Standort & Kompass
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var location: CLLocation?
    private(set) var heading: CLHeading?

    // Barometer / Höhenmesser
    private(set) var pressureKPa: Double?
    private(set) var relativeAltitude: Double?
    private(set) var absoluteAltitude: Double?
    private(set) var absoluteAccuracy: Double?
    private(set) var hasBarometer = CMAltimeter.isRelativeAltitudeAvailable()

    // Bewegung
    private(set) var gravity = SIMD3<Double>(0, -1, 0)
    private(set) var attitude = SIMD3<Double>(0, 0, 0)
    private(set) var rotationRate: Double = 0
    private(set) var userAcceleration: Double = 0
    private(set) var magneticField: Double?
    private(set) var magneticAccuracy: CMMagneticFieldCalibrationAccuracy = .uncalibrated
    private(set) var activity: String?
    private(set) var isWalking = false
    private(set) var floorsAscended = 0
    private(set) var floorsDescended = 0
    private(set) var steps = 0

    // LiDAR / Kamera (aus ARKit gemeldet)
    private(set) var lastCeilingSeen: Date?
    private(set) var lastSkySeen: Date?
    private(set) var measuredRoomHeight: Float?
    private(set) var ambientIntensity: Double?
    private(set) var colorTemperature: Double?
    private(set) var lastLightUpdate: Date?
    private(set) var lastLiDARActivity: Date?

    // System
    private(set) var thermalState = ProcessInfo.processInfo.thermalState
    private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var batteryLevel: Float = UIDevice.current.batteryLevel

    // Kalibrierung
    private(set) var calibration: FloorCalibration?
    private(set) var placeOverride: PlaceOverride

    func setPlaceOverride(_ value: PlaceOverride) {
        placeOverride = value
        UserDefaults.standard.set(value.rawValue, forKey: "placeOverride")
    }

    private let locationManager = CLLocationManager()
    private let locationProxy = LocationProxy()
    private let altimeter = CMAltimeter()
    private let motionManager = CMMotionManager()
    private let activityManager = CMMotionActivityManager()
    private let pedometer = CMPedometer()

    private var isRunning = false
    private var motionUsers = 0
    private var preciseUsers = 0
    private var lastARReport: TimeInterval = 0
    private var lastAutoCalibration: Date?
    private var observers: [NSObjectProtocol] = []

    private init() {
        placeOverride = PlaceOverride(rawValue: UserDefaults.standard.string(forKey: "placeOverride") ?? "") ?? .auto
        if let data = UserDefaults.standard.data(forKey: "floorCalibration") {
            calibration = try? JSONDecoder().decode(FloorCalibration.self, from: data)
        }
        locationProxy.hub = self
        locationManager.delegate = locationProxy
        locationManager.activityType = .fitness
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.headingFilter = 2
        authorization = locationManager.authorizationStatus
    }

    // MARK: Lebenszyklus

    /// Startet die energiearmen Dauer-Sensoren (App im Vordergrund).
    func start() {
        guard !isRunning else { return }
        isRunning = true

        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        applyLocationAccuracy()
        locationManager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }

        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                MainActor.assumeIsolated { self?.didUpdatePressure(data) }
            }
        }
        if CMAltimeter.isAbsoluteAltitudeAvailable() {
            altimeter.startAbsoluteAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                MainActor.assumeIsolated {
                    self?.absoluteAltitude = data.altitude
                    self?.absoluteAccuracy = data.accuracy
                }
            }
        }
        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: .main) { [weak self] activity in
                guard let activity else { return }
                MainActor.assumeIsolated { self?.didUpdate(activity: activity) }
            }
        }
        startPedometer()

        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.thermalState = ProcessInfo.processInfo.thermalState; self?.applyLocationAccuracy() }
            },
            center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled; self?.applyLocationAccuracy() }
            },
            center.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.batteryLevel = UIDevice.current.batteryLevel }
            }
        ]
        if motionUsers > 0 { startMotion() }
    }

    /// Stoppt alle Sensoren (App im Hintergrund).
    func stop() {
        guard isRunning else { return }
        isRunning = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        altimeter.stopRelativeAltitudeUpdates()
        altimeter.stopAbsoluteAltitudeUpdates()
        activityManager.stopActivityUpdates()
        pedometer.stopUpdates()
        motionManager.stopDeviceMotionUpdates()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    /// Hochfrequente Bewegungssensoren (Gyro, Beschleunigung, Magnetometer) nur bei Bedarf.
    func acquireMotion() {
        motionUsers += 1
        if motionUsers == 1, isRunning { startMotion() }
    }

    func releaseMotion() {
        motionUsers = max(0, motionUsers - 1)
        if motionUsers == 0 { motionManager.stopDeviceMotionUpdates() }
    }

    /// Hochgenaues GPS nur, solange ein Scan oder die Sensoransicht offen ist.
    func acquirePrecision() {
        preciseUsers += 1
        applyLocationAccuracy()
    }

    func releasePrecision() {
        preciseUsers = max(0, preciseUsers - 1)
        applyLocationAccuracy()
    }

    private func applyLocationAccuracy() {
        let throttled = lowPowerMode || thermalState == .serious || thermalState == .critical
        if preciseUsers > 0 && !throttled {
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.distanceFilter = 2
        } else {
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.distanceFilter = 10
        }
    }

    private func startMotion() {
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else { return }
        let throttled = lowPowerMode || thermalState == .serious || thermalState == .critical
        motionManager.deviceMotionUpdateInterval = throttled ? 1.0 / 15.0 : 1.0 / 30.0
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xMagneticNorthZVertical) ? .xMagneticNorthZVertical : .xArbitraryCorrectedZVertical
        motionManager.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated { self?.didUpdate(motion: motion) }
        }
    }

    private func startPedometer() {
        guard CMPedometer.isStepCountingAvailable() || CMPedometer.isFloorCountingAvailable() else { return }
        pedometer.stopUpdates()
        floorsAscended = 0
        floorsDescended = 0
        steps = 0
        let start = calibration?.date ?? Date()
        // Der Schrittzähler liefert höchstens 7 Tage Verlauf.
        let from = max(start, Date().addingTimeInterval(-6.5 * 24 * 3600))
        pedometer.startUpdates(from: from) { [weak self] data, _ in
            guard let data else { return }
            let up = data.floorsAscended?.intValue ?? 0
            let down = data.floorsDescended?.intValue ?? 0
            let steps = data.numberOfSteps.intValue
            DispatchQueue.main.async {
                self?.floorsAscended = up
                self?.floorsDescended = down
                self?.steps = steps
            }
        }
    }

    // MARK: Eingänge

    fileprivate func didUpdate(location: CLLocation) {
        guard location.horizontalAccuracy >= 0 else { return }
        self.location = location
        considerAutoCalibration()
    }

    fileprivate func didUpdate(heading: CLHeading) {
        self.heading = heading
    }

    fileprivate func didChangeAuthorization(_ status: CLAuthorizationStatus) {
        authorization = status
        if isRunning, status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }

    private func didUpdatePressure(_ data: CMAltitudeData) {
        let p = data.pressure.doubleValue
        // leichte Glättung gegen Rauschen
        if let old = pressureKPa {
            pressureKPa = old * 0.7 + p * 0.3
        } else {
            pressureKPa = p
        }
        relativeAltitude = data.relativeAltitude.doubleValue
    }

    private func didUpdate(activity: CMMotionActivity) {
        isWalking = activity.walking || activity.running
        if activity.walking { self.activity = "Gehen" }
        else if activity.running { self.activity = "Laufen" }
        else if activity.cycling { self.activity = "Radfahren" }
        else if activity.automotive { self.activity = "Fahrzeug" }
        else if activity.stationary { self.activity = "Ruhend" }
        else { self.activity = "Unbekannt" }
    }

    private func didUpdate(motion: CMDeviceMotion) {
        gravity = SIMD3<Double>(motion.gravity.x, motion.gravity.y, motion.gravity.z)
        attitude = SIMD3<Double>(motion.attitude.pitch, motion.attitude.roll, motion.attitude.yaw)
        let r = motion.rotationRate
        rotationRate = sqrt(r.x * r.x + r.y * r.y + r.z * r.z)
        let a = motion.userAcceleration
        userAcceleration = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
        let field = motion.magneticField
        if field.accuracy != .uncalibrated {
            let f = field.field
            magneticField = sqrt(f.x * f.x + f.y * f.y + f.z * f.z)
        }
        magneticAccuracy = field.accuracy
    }

    /// Wird von allen AR-Sitzungen aufgerufen (Hauptthread). Wertet LiDAR-Ebenen
    /// und das Kameralicht aus – gedrosselt auf 1 Hz.
    func reportAR(frame: ARFrame) {
        let now = frame.timestamp
        guard now - lastARReport > 1.0 else { return }
        lastARReport = now

        if let light = frame.lightEstimate {
            ambientIntensity = Double(light.ambientIntensity)
            colorTemperature = Double(light.ambientColorTemperature)
            lastLightUpdate = Date()
        }
        if frame.sceneDepth != nil || frame.smoothedSceneDepth != nil {
            lastLiDARActivity = Date()
        }

        let cameraY = frame.camera.transform.columns.3.y
        var ceilingYs: [Float] = []
        var floorYs: [Float] = []
        var meshCeiling = false
        for anchor in frame.anchors {
            if let plane = anchor as? ARPlaneAnchor {
                switch plane.classification {
                case .ceiling: ceilingYs.append(plane.transform.columns.3.y)
                case .floor: floorYs.append(plane.transform.columns.3.y)
                default: break
                }
            } else if !meshCeiling, let mesh = anchor as? ARMeshAnchor, mesh.transform.columns.3.y > cameraY + 0.3 {
                meshCeiling = Self.containsCeiling(mesh.geometry)
            }
        }

        let ceiling = ceilingYs.filter { $0 > cameraY + 0.15 }.min()
        if ceiling != nil || meshCeiling {
            lastCeilingSeen = Date()
            lastLiDARActivity = Date()
        }
        if let ceiling, let floor = floorYs.filter({ $0 < cameraY - 0.3 }).max() {
            let height = ceiling - floor
            if height > 1.9 && height < 6 {
                measuredRoomHeight = measuredRoomHeight.map { $0 * 0.8 + height * 0.2 } ?? height
            }
        }
    }

    private static func containsCeiling(_ geometry: ARMeshGeometry) -> Bool {
        guard let source = geometry.classification else { return false }
        let base = source.buffer.contents().advanced(by: source.offset)
        let ceiling = UInt8(ARMeshClassification.ceiling.rawValue)
        let step = max(1, source.count / 200)
        var i = 0
        while i < source.count {
            if base.load(fromByteOffset: i * source.stride, as: UInt8.self) == ceiling { return true }
            i += step
        }
        return false
    }

    /// RoomPlan funktioniert nur in Innenräumen und liefert eine verlässliche Raumhöhe.
    func reportRoomPlan(height: Float) {
        lastCeilingSeen = Date()
        if height > 1.9 && height < 6 { measuredRoomHeight = height }
    }

    // MARK: Drinnen / Draußen

    var assessment: PlaceAssessment {
        switch placeOverride {
        case .indoor:
            return PlaceAssessment(place: .indoor, confidence: 1, evidence: [Evidence(text: "Manuell auf „Drinnen“ gesetzt", icon: "hand.raised.fill", weight: 5)])
        case .outdoor:
            return PlaceAssessment(place: .outdoor, confidence: 1, evidence: [Evidence(text: "Manuell auf „Draußen“ gesetzt", icon: "hand.raised.fill", weight: -5)])
        case .auto:
            break
        }

        var evidence: [Evidence] = []
        let now = Date()

        // 1. LiDAR: Decke über dem Gerät ist der stärkste Hinweis.
        if let seen = lastCeilingSeen, now.timeIntervalSince(seen) < 15 * 60 {
            let heightText = measuredRoomHeight.map { " · Raumhöhe \(Units.length($0))" } ?? ""
            evidence.append(Evidence(text: "LiDAR hat eine Decke erkannt\(heightText)", icon: "light.recessed", weight: 3.5))
        }

        // 2. GPS-Qualität
        if let loc = location, now.timeIntervalSince(loc.timestamp) < 90 {
            let acc = loc.horizontalAccuracy
            let accText = "±\(Int(acc.rounded())) m"
            if acc <= 8 {
                evidence.append(Evidence(text: "Sehr gutes GPS-Signal (\(accText))", icon: "location.fill", weight: -2))
            } else if acc <= 15 {
                evidence.append(Evidence(text: "Gutes GPS-Signal (\(accText))", icon: "location.fill", weight: -0.8))
            } else if acc > 100 {
                evidence.append(Evidence(text: "Kaum GPS-Empfang (\(accText)) – typisch in Gebäuden", icon: "location.slash.fill", weight: 1.8))
            } else if acc > 35 {
                evidence.append(Evidence(text: "Schwaches GPS-Signal (\(accText))", icon: "location", weight: 1.0))
            }
            if let floor = loc.floor {
                evidence.append(Evidence(text: "Apple-Gebäudekarte: \(FloorName.name(floor.level))", icon: "building.2.crop.circle", weight: 3))
            }
        } else if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
            evidence.append(Evidence(text: "Kein aktueller GPS-Fix", icon: "location.slash", weight: 0.8))
        }

        // 3. Licht (Farbtemperatur & Helligkeit aus der Kamera)
        if let updated = lastLightUpdate, now.timeIntervalSince(updated) < 5 * 60,
           let temp = colorTemperature, let intensity = ambientIntensity {
            let kelvin = "\(Int(temp)) K"
            if temp >= 5300 && intensity >= 1500 {
                evidence.append(Evidence(text: "Helles Tageslicht (\(kelvin))", icon: "sun.max", weight: -1.2))
            } else if temp <= 4200 {
                evidence.append(Evidence(text: "Warmes Kunstlicht (\(kelvin))", icon: "lightbulb.fill", weight: 0.8))
            } else if intensity < 400 {
                evidence.append(Evidence(text: "Gedämpftes Licht", icon: "moon.fill", weight: 0.4))
            }
        }

        // 4. Barometer: deutlich über der Kalibrier-Etage = sicher im Gebäude
        if let estimate = floorEstimateIfCalibrated, let f = estimate.floor, f >= 1 {
            evidence.append(Evidence(text: "Barometer: \(FloorName.name(f))", icon: "barometer", weight: 1.5))
        }

        let score = evidence.reduce(0) { $0 + $1.weight }
        let confidence = min(1, abs(score) / 3.0)
        let place: PlaceKind = score >= 1 ? .indoor : (score <= -1 ? .outdoor : .unknown)
        return PlaceAssessment(place: place, confidence: confidence, evidence: evidence.sorted { abs($0.weight) > abs($1.weight) })
    }

    // MARK: Etage

    /// Etagenhöhe: manuell, aus LiDAR/RoomPlan gemessen (+ Deckenstärke) oder 3 m.
    var floorHeight: Double {
        let manual = UserDefaults.standard.double(forKey: "floorHeight")
        if manual > 0 { return manual }
        if let measured = measuredRoomHeight, measured > 2.1, measured < 4.5 {
            return Double(measured) + 0.3
        }
        return 3.0
    }

    var floorHeightSource: String {
        if UserDefaults.standard.double(forKey: "floorHeight") > 0 { return "manuell" }
        if let m = measuredRoomHeight, m > 2.1, m < 4.5 { return "LiDAR-gemessen" }
        return "Standard"
    }

    var floorEstimate: FloorEstimate {
        if let loc = location, Date().timeIntervalSince(loc.timestamp) < 120, let floor = loc.floor {
            return FloorEstimate(floor: floor.level, source: "Apple-Gebäudekarte", heightAboveReference: nil, warning: nil)
        }
        if let estimate = floorEstimateIfCalibrated { return estimate }
        if !hasBarometer {
            return FloorEstimate(floor: nil, source: "Kein Barometer", heightAboveReference: nil, warning: nil)
        }
        return FloorEstimate(floor: nil, source: "Nicht kalibriert", heightAboveReference: nil, warning: "Tippe auf „Kalibrieren“ und gib einmal deine aktuelle Etage an.")
    }

    private var floorEstimateIfCalibrated: FloorEstimate? {
        guard let cal = calibration else { return nil }
        let age = Date().timeIntervalSince(cal.date)
        let source = cal.automatic ? "Barometer (auto-kalibriert)" : "Barometer"

        // a) Wetterbedingte Luftdruck-Drift: nach > 1 h wird die GPS-gestützte
        //    absolute Höhe oder der Stockwerkzähler bevorzugt.
        if age > 3600 {
            if let abs = absoluteAltitude, let acc = absoluteAccuracy, acc <= 8, let ref = cal.absoluteAltitude {
                let delta = abs - ref
                return FloorEstimate(floor: cal.floor + Int((delta / floorHeight).rounded()), source: "Höhenmesser (GPS-korrigiert)", heightAboveReference: delta, warning: nil)
            }
            if CMPedometer.isFloorCountingAvailable() {
                let floors = floorsAscended - floorsDescended
                return FloorEstimate(floor: cal.floor + floors, source: "Stockwerkzähler", heightAboveReference: Double(floors) * floorHeight, warning: age > 6 * 3600 ? "Kalibrierung ist älter als 6 h – ggf. neu kalibrieren." : nil)
            }
        }

        // b) Barometrische Höhenformel relativ zur Kalibrierung
        guard let p = pressureKPa, p > 0 else {
            return FloorEstimate(floor: cal.floor, source: "Kalibriert (warte auf Barometer)", heightAboveReference: nil, warning: nil)
        }
        let delta = 8434.5 * log(cal.pressureKPa / p)
        let floor = cal.floor + Int((delta / floorHeight).rounded())
        let warning = age > 3 * 3600 ? "Luftdruck kann sich durch Wetter ändern – neu kalibrieren für beste Genauigkeit." : nil
        return FloorEstimate(floor: floor, source: source, heightAboveReference: delta, warning: warning)
    }

    func calibrate(floor: Int, automatic: Bool = false) {
        guard let p = pressureKPa else { return }
        let cal = FloorCalibration(
            floor: floor,
            pressureKPa: p,
            absoluteAltitude: (absoluteAccuracy ?? 99) <= 10 ? absoluteAltitude : nil,
            date: Date(),
            automatic: automatic
        )
        calibration = cal
        if let data = try? JSONEncoder().encode(cal) {
            UserDefaults.standard.set(data, forKey: "floorCalibration")
        }
        if isRunning { startPedometer() }
    }

    func resetCalibration() {
        calibration = nil
        UserDefaults.standard.removeObject(forKey: "floorCalibration")
    }

    /// Auto-Kalibrierung: Nur bei eindeutig „draußen“ (sehr gutes GPS, Gehen,
    /// keine Decke gesehen) wird Bodenniveau = Erdgeschoss angenommen.
    private func considerAutoCalibration() {
        guard UserDefaults.standard.object(forKey: "autoFloorCalibration") as? Bool ?? true,
              placeOverride != .indoor,
              pressureKPa != nil,
              isWalking,
              let loc = location,
              loc.horizontalAccuracy <= 6,
              loc.verticalAccuracy > 0, loc.verticalAccuracy <= 8 else { return }
        if let seen = lastCeilingSeen, Date().timeIntervalSince(seen) < 15 * 60 { return }
        if let last = lastAutoCalibration, Date().timeIntervalSince(last) < 5 * 60 { return }
        if let cal = calibration, !cal.automatic, Date().timeIntervalSince(cal.date) < 12 * 3600 { return }
        let a = assessment
        guard a.place == .outdoor, a.confidence >= 0.6 else { return }
        lastAutoCalibration = Date()
        calibrate(floor: 0, automatic: true)
    }

    // MARK: Schnappschuss

    func snapshot() -> EnvironmentSnapshot {
        let a = assessment
        let f = floorEstimate
        let fresh = location.flatMap { Date().timeIntervalSince($0.timestamp) < 300 ? $0 : nil }
        return EnvironmentSnapshot(
            latitude: fresh?.coordinate.latitude,
            longitude: fresh?.coordinate.longitude,
            horizontalAccuracy: fresh?.horizontalAccuracy,
            altitude: absoluteAltitude ?? fresh?.altitude,
            pressureKPa: pressureKPa,
            floor: f.floor,
            floorSource: f.floor != nil ? f.source : nil,
            place: a.place,
            placeConfidence: a.confidence,
            heading: heading.map { $0.trueHeading >= 0 ? $0.trueHeading : $0.magneticHeading },
            roomHeight: measuredRoomHeight
        )
    }

    // MARK: Abgeleitete Werte

    /// Neigung des Geräts in Grad (0° = flach liegend / genau senkrecht, je nach Lage).
    var tilt: (x: Double, y: Double, flat: Bool) {
        let g = gravity
        let flat = abs(g.z) > 0.8
        if flat {
            return (asin(max(-1, min(1, g.x))) * 180 / .pi, asin(max(-1, min(1, g.y))) * 180 / .pi, true)
        }
        let angle = atan2(g.x, -g.y) * 180 / .pi
        let forward = asin(max(-1, min(1, g.z))) * 180 / .pi
        return (angle, forward, false)
    }

    var compassHeading: Double? {
        guard let heading else { return nil }
        return heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
    }

    /// Faktor für rechenintensive Arbeit: 1 = normal, größer = seltener arbeiten.
    nonisolated static var throttleFactor: Double {
        let info = ProcessInfo.processInfo
        switch info.thermalState {
        case .critical: return 4
        case .serious: return 2.5
        case .fair: return info.isLowPowerModeEnabled ? 2 : 1.3
        default: return info.isLowPowerModeEnabled ? 1.8 : 1
        }
    }
}

private final class LocationProxy: NSObject, CLLocationManagerDelegate {
    weak var hub: SensorHub?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        MainActor.assumeIsolated { hub?.didUpdate(location: last) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        MainActor.assumeIsolated { hub?.didUpdate(heading: newHeading) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { hub?.didChangeAuthorization(status) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }
}
