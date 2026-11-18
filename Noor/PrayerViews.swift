import SwiftUI
import CoreLocation
import CoreMotion
import NoorKit

// MARK: - times

struct TimesView: View {
    @ObservedObject private var store = Store.shared
    @StateObject private var loc = LocationKeeper()
    @State private var now = Date()
    @State private var showSettings = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var calc: PrayerCalc {
        PrayerCalc(.init(lat: store.lat, lon: store.lon, method: store.method, offsets: store.offsets))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Card {
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack {
                            Text(PrayerCalc.hijri(now)).font(.system(size: 12)).foregroundStyle(P.sub)
                            Spacer()
                            Text(store.cityName).font(.system(size: 12, weight: .bold)).foregroundStyle(P.gold)
                        }
                        Text(clockNow).font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(P.txt)
                        let n = calc.next(now: now)
                        HStack(spacing: 6) {
                            Text("الصلاة القادمة: \(PrayerCalc.names[n.index])")
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(P.teal)
                            Text("· باقي \(PrayerCalc.countdown(n.remaining))")
                                .font(.system(size: 12)).foregroundStyle(P.sub)
                        }
                    }
                }

                let t = calc.todayTimes(now: now)
                let n = calc.next(now: now)
                Card {
                    VStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { i in
                            HStack {
                                Text(PrayerCalc.clock(t[i]))
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(i == n.index ? P.gold : P.txt)
                                Spacer()
                                Text(PrayerCalc.names[i])
                                    .font(.system(size: 13, weight: i == n.index ? .bold : .regular))
                                    .foregroundStyle(i == n.index ? P.gold : P.sub)
                                Image(systemName: i == n.index ? "bell.fill" : "circle")
                                    .font(.system(size: 10)).foregroundStyle(i == n.index ? P.gold : P.card2)
                            }
                            .padding(.vertical, 9)
                            if i < 5 { Divider().overlay(P.card2) }
                        }
                    }
                }

                HStack(spacing: 8) {
                    GoldButton(title: "⚙︎ طريقة الحساب والتعديل") { showSettings = true }
                }
                if !loc.denied.isBlank {
                    Text(loc.denied).font(.system(size: 10)).foregroundStyle(P.amber)
                }
                Text("كل الحساب على الجهاز، بدون إنترنت. الطريقة: \(PrayerCalc.methods[max(0, min(PrayerCalc.methods.count-1, store.method))].name)")
                    .font(.system(size: 10)).foregroundStyle(P.sub)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 14).padding(.bottom, 26).padding(.top, 6)
        }
        .onReceive(timer) { now = $0 }
        .sheet(isPresented: $showSettings) { PrayerSettings() }
        .task { loc.request(store: store) }
    }

    private var clockNow: String {
        let c = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: now)
        let h = c.hour! % 12 == 0 ? 12 : c.hour! % 12
        return "\(fmt(h)):\(c.minute! < 10 ? "٠" : "")\(fmt(c.minute!)) \(c.hour! < 12 ? "ص" : "م")"
    }
}

struct PrayerSettings: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("المدينة") {
                    TextField("اسم المدينة", text: $store.cityName)
                    HStack { Text("خط العرض"); Spacer(); Text(String(format: "%.4f", store.lat)).foregroundStyle(.secondary) }
                    HStack { Text("خط الطول"); Spacer(); Text(String(format: "%.4f", store.lon)).foregroundStyle(.secondary) }
                }
                Section("طريقة الحساب") {
                    Picker("الطريقة", selection: $store.method) {
                        ForEach(Array(PrayerCalc.methods.enumerated()), id: \.offset) { i, m in
                            Text(m.name).tag(i)
                        }
                    }
                }
                Section("تعديل بالدقائق") {
                    ForEach(0..<6, id: \.self) { i in
                        Stepper("\(PrayerCalc.names[i]): \(store.offsets[i] >= 0 ? "+" : "")\(fmt(store.offsets[i])) د",
                                value: Binding(get: { store.offsets[i] },
                                               set: { var o = store.offsets; o[i] = $0; store.offsets = o }),
                                in: -30...30)
                    }
                }
                Section("التنبيهات") {
                    Toggle("تنبيه قبل الأذان", isOn: $store.alarmsOn)
                    Stepper("قبل الصلاة بـ \(fmt(store.preMinutes)) دقيقة", value: $store.preMinutes, in: 0...30)
                    Text("الإشعارات بتتفعّل من إعدادات النظام — التطبيق بيحسب المواقيت بدون إنترنت.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("الإعدادات")
            .toolbar { Button("تمام") { dismiss() } }
        }
    }
}

// MARK: - location

final class LocationKeeper: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var denied = ""
    private let mgr = CLLocationManager()
    weak var store: Store?

    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request(store: Store) {
        self.store = store
        mgr.requestWhenInUseAuthorization()
        mgr.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let loc = locs.last else { return }
        DispatchQueue.main.async {
            self.store?.lat = loc.coordinate.latitude
            self.store?.lon = loc.coordinate.longitude
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.denied = "لو عايز المواقيت مضبوطة على مكانك: الإعدادات ← نور ← الموقع."
        }
    }
}

// MARK: - qibla

struct QiblaView: View {
    @ObservedObject private var store = Store.shared
    @StateObject private var motion = HeadingKeeper()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card {
                    VStack(spacing: 10) {
                        Text("🧭 القبلة").font(.system(size: 16, weight: .bold)).foregroundStyle(P.gold)
                        ZStack {
                            Circle().stroke(P.card2, lineWidth: 12)
                            Circle().trim(from: 0, to: 0.25).stroke(P.teal.opacity(0.25), lineWidth: 12)
                            // the needle, rotated relative to the device heading
                            VStack {
                                Image(systemName: "location.north.fill")
                                    .font(.system(size: 46))
                                    .foregroundStyle(P.gold)
                                Spacer()
                            }
                            .padding(.top, 10)
                            .rotationEffect(.degrees(qibla - motion.heading))
                        }
                        .frame(width: 230, height: 230)
                        Text("القبلة على \(fmt(Int(qibla.rounded())))° من الشمال")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(P.txt)
                        Text(motion.available ? "حرّك الموبايل ببطء — السهم بيوضّح اتجاه الكعبة"
                             : "البوصلة مش متاحة — اضبط الشمال يدويًا: اتجاه القبلة \(fmt(Int(qibla.rounded())))°")
                            .font(.system(size: 11)).foregroundStyle(P.sub).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
                Card {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("الإحداثيات الحالية").font(.system(size: 12, weight: .bold)).foregroundStyle(P.gold)
                        Text("\(String(format: "%.4f", store.lat)) , \(String(format: "%.4f", store.lon))")
                            .font(.system(size: 11)).foregroundStyle(P.sub)
                        Text("المسافة للكعبة: \(fmt(kilometers)) كم").font(.system(size: 11)).foregroundStyle(P.sub)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 26)
        }
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }

    private var qibla: Double {
        PrayerCalc(.init(lat: store.lat, lon: store.lon, method: store.method)).qiblaBearing()
    }

    private var kilometers: Int {
        let kaaba = (lat: 21.4225, lon: 39.8262)
        let R = 6371.0
        let dLat = (kaaba.lat - store.lat) * .pi / 180
        let dLon = (kaaba.lon - store.lon) * .pi / 180
        let a = sin(dLat/2) * sin(dLat/2)
              + cos(store.lat * .pi/180) * cos(kaaba.lat * .pi/180) * sin(dLon/2) * sin(dLon/2)
        return Int(2 * R * atan2(sqrt(a), sqrt(1-a)))
    }
}

final class HeadingKeeper: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var heading: Double = 0
    @Published var available = false
    private let mgr = CLLocationManager()

    override init() {
        super.init()
        mgr.delegate = self
        mgr.headingFilter = 1
        available = CLLocationManager.headingAvailable()
    }

    func start() {
        available = CLLocationManager.headingAvailable()
        if CLLocationManager.headingAvailable() { mgr.startUpdatingHeading() }
    }
    func stop() { mgr.stopUpdatingHeading() }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading.magneticHeading
    }
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }
}

extension String { var isBlank: Bool { trimmingCharacters(in: .whitespaces).isEmpty } }
