//
//  WeatherCardView.swift
//  lifelog
//
//  Created by Codex on 2025/12/05.
//

import SwiftUI
import CoreLocation

private typealias AsyncTask = _Concurrency.Task

/// ホーム画面に表示する天気カード
struct WeatherCardView: View {
    @ObservedObject var weatherService: WeatherService
    
    var body: some View {
        Group {
            if let weather = weatherService.currentWeather {
                weatherContent(weather)
            } else if weatherService.isLoading {
                loadingView
            } else if weatherService.locationStatus == .notDetermined {
                permissionRequestView
            } else if weatherService.locationStatus == .denied || weatherService.locationStatus == .restricted {
                locationDeniedView
            } else if let error = weatherService.errorMessage {
                errorView(error)
            } else {
                emptyView
            }
        }
    }
    
    private func weatherContent(_ weather: CurrentWeatherData) -> some View {
        HStack(spacing: 12) {
            // 天気アイコン
            Image(systemName: weather.symbolName)
                .font(.system(size: 32))
                .symbolRenderingMode(.multicolor)
            
            VStack(alignment: .leading, spacing: 2) {
                // 天気状態
                Text(weather.conditionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // 現在の気温
                Text(weather.temperatureString)
                    .font(.title2.bold())
            }
            
            Spacer()
            
            // 最高・最低気温
            if let highLow = weather.highLowString {
                Text(highLow)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
    
    private var loadingView: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("天気情報を取得中...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
    
    private var permissionRequestView: some View {
        Button {
            weatherService.requestLocationPermission()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "location.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("天気を表示")
                        .font(.subheadline.weight(.medium))
                    Text("位置情報を許可してください")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
    
    private var locationDeniedView: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("位置情報が許可されていません")
                    .font(.subheadline)
                Text("設定から位置情報を許可すると天気が表示されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
    
    private func errorView(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                AsyncTask {
                    await weatherService.fetchWeather()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
    
    private var emptyView: some View {
        Button {
            AsyncTask {
                await weatherService.fetchWeather()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "cloud.sun")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("天気情報を取得")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

