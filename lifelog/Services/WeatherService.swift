//
//  WeatherService.swift
//  lifelog
//
//  Created by Codex on 2025/12/05.
//

import Foundation
import WeatherKit
import CoreLocation
import Combine
import os

/// 天気情報を取得・管理するサービス
final class WeatherService: NSObject, ObservableObject {
    @Published private(set) var currentWeather: CurrentWeatherData?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var locationStatus: CLAuthorizationStatus = .notDetermined
    
    // Home can render its header before the launch animation finishes. Initialize
    // the system services only when Home refreshes or setup requests access.
    private lazy var weatherKitService = WeatherKit.WeatherService.shared
    private lazy var locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self
        return manager
    }()
    private var lastFetchDate: Date?

    override init() {
        super.init()
        #if DEBUG && targetEnvironment(simulator)
        if ASOScreenshotShowcase.isEnabled {
            currentWeather = CurrentWeatherData(
                condition: .clear,
                symbolName: "sun.max.fill",
                temperature: 18,
                temperatureUnit: "°C",
                highTemperature: 21,
                lowTemperature: 12
            )
        }
        #endif
    }

    /// Invoked from the Home weather action. Background refreshes never ask for permission.
    func requestLocationPermission() {
        guard locationManager.authorizationStatus == .notDetermined else { return }
        locationManager.requestWhenInUseAuthorization()
    }

    func requestLocationPermissionForSetup() async -> Bool {
        let status = locationManager.authorizationStatus
        guard status == .notDetermined else {
            return status == .authorizedWhenInUse || status == .authorizedAlways
        }
        requestLocationPermission()
        for await status in $locationStatus.values where status != .notDetermined {
            return status == .authorizedWhenInUse || status == .authorizedAlways
        }
        return false
    }

    /// 天気情報を取得
    func fetchWeather() async {
        #if DEBUG && targetEnvironment(simulator)
        if ASOScreenshotShowcase.isEnabled {
            currentWeather = CurrentWeatherData(
                condition: .clear,
                symbolName: "sun.max.fill",
                temperature: 18,
                temperatureUnit: "°C",
                highTemperature: 21,
                lowTemperature: 12
            )
            return
        }
        #endif
        let status = locationManager.authorizationStatus
        if locationStatus != status { locationStatus = status }
        guard !isLoading else { return }
        guard locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways else { return }
        
        // 10分以内に取得済みならスキップ
        if let lastFetch = lastFetchDate, Date().timeIntervalSince(lastFetch) < 600 {
            return
        }
        
        guard let location = locationManager.location else {
            isLoading = true
            locationManager.requestLocation()
            return
        }
        
        await fetchWeather(for: location)
    }
    
    private func fetchWeather(for location: CLLocation) async {
        guard locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        
        do {
            let weather = try await weatherKitService.weather(for: location)
            guard locationManager.authorizationStatus == .authorizedWhenInUse ||
                    locationManager.authorizationStatus == .authorizedAlways else { return }
            
            let current = weather.currentWeather
            let today = weather.dailyForecast.first
            
            currentWeather = CurrentWeatherData(
                condition: current.condition,
                symbolName: current.symbolName,
                temperature: current.temperature.value,
                temperatureUnit: "°C",
                highTemperature: today?.highTemperature.value,
                lowTemperature: today?.lowTemperature.value
            )
            
            lastFetchDate = Date()
        } catch {
            errorMessage = String(localized: "天気情報を取得できませんでした")
            AppLogger.general.error("WeatherKit Error: \(error)")
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        _Concurrency.Task { @MainActor in
            self.locationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                await self.fetchWeather()
            } else {
                self.currentWeather = nil
                self.lastFetchDate = nil
                self.isLoading = false
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        _Concurrency.Task { @MainActor in
            await self.fetchWeather(for: location)
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        _Concurrency.Task { @MainActor in
            self.errorMessage = String(localized: "位置情報を取得できませんでした")
            self.isLoading = false
        }
    }
}

// MARK: - Data Model

struct CurrentWeatherData {
    let condition: WeatherCondition
    let symbolName: String
    let temperature: Double
    let temperatureUnit: String
    let highTemperature: Double?
    let lowTemperature: Double?
    
    var temperatureString: String {
        String(format: "%.0f%@", temperature, temperatureUnit)
    }
    
    var highLowString: String? {
        guard let high = highTemperature, let low = lowTemperature else { return nil }
        return String(format: "H:%.0f° L:%.0f°", high, low)
    }

    /// コンパクト形式: 20°/15°
    var compactHighLowString: String? {
        guard let high = highTemperature, let low = lowTemperature else { return nil }
        return String(format: "%.0f°/%.0f°", high, low)
    }

    /// 数字のみ: 20/15
    var numericHighLowString: String? {
        guard let high = highTemperature, let low = lowTemperature else { return nil }
        return String(format: "%.0f/%.0f", high, low)
    }
    
    var conditionDescription: String {
        switch condition {
        case .clear: return String(localized: "晴れ")
        case .mostlyClear: return String(localized: "おおむね晴れ")
        case .partlyCloudy: return String(localized: "一部曇り")
        case .mostlyCloudy: return String(localized: "おおむね曇り")
        case .cloudy: return String(localized: "曇り")
        case .rain: return String(localized: "雨")
        case .drizzle: return String(localized: "霧雨")
        case .heavyRain: return String(localized: "大雨")
        case .snow: return String(localized: "雪")
        case .heavySnow: return String(localized: "大雪")
        case .sleet: return String(localized: "みぞれ")
        case .thunderstorms: return String(localized: "雷雨")
        case .foggy: return String(localized: "霧")
        case .haze: return String(localized: "もや")
        case .windy: return String(localized: "強風")
        case .hot: return String(localized: "猛暑")
        case .frigid: return String(localized: "極寒")
        default: return String(localized: "不明")
        }
    }
}
