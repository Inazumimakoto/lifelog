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

/// 天気情報を取得・管理するサービス
final class WeatherService: NSObject, ObservableObject {
    @Published private(set) var currentWeather: CurrentWeatherData?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var locationStatus: CLAuthorizationStatus = .notDetermined
    
    private let weatherKitService = WeatherKit.WeatherService.shared
    private let locationManager = CLLocationManager()
    private var lastFetchDate: Date?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    
    /// 位置情報の許可をリクエスト
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    /// 天気情報を取得
    func fetchWeather() async {
        guard locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways else {
            requestLocationPermission()
            return
        }
        
        // 10分以内に取得済みならスキップ
        if let lastFetch = lastFetchDate, Date().timeIntervalSince(lastFetch) < 600 {
            return
        }
        
        guard let location = locationManager.location else {
            locationManager.requestLocation()
            return
        }
        
        await fetchWeather(for: location)
    }
    
    private func fetchWeather(for location: CLLocation) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let weather = try await weatherKitService.weather(for: location)
            
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
            errorMessage = "天気情報を取得できませんでした"
            print("WeatherKit Error: \(error)")
        }
        
        isLoading = false
    }
}

// MARK: - CLLocationManagerDelegate

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        _Concurrency.Task { @MainActor in
            self.locationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                await self.fetchWeather()
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
            self.errorMessage = "位置情報を取得できませんでした"
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
        case .clear: return "晴れ"
        case .mostlyClear: return "おおむね晴れ"
        case .partlyCloudy: return "一部曇り"
        case .mostlyCloudy: return "おおむね曇り"
        case .cloudy: return "曇り"
        case .rain: return "雨"
        case .drizzle: return "霧雨"
        case .heavyRain: return "大雨"
        case .snow: return "雪"
        case .heavySnow: return "大雪"
        case .sleet: return "みぞれ"
        case .thunderstorms: return "雷雨"
        case .foggy: return "霧"
        case .haze: return "もや"
        case .windy: return "強風"
        case .hot: return "猛暑"
        case .frigid: return "極寒"
        default: return "不明"
        }
    }
}
