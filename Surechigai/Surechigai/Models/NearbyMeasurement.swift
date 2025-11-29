//
//  NearbyMeasurement.swift
//  Surechigai
//
//  Created on 2025/11/29.
//

import Foundation
import simd

/// UWBによる測距結果を表すモデル
struct NearbyMeasurement {
    /// 距離（メートル）
    let distance: Float?

    /// 方向ベクトル（正規化済み）
    let direction: simd_float3?

    /// 測定時刻
    let timestamp: Date

    /// 距離が有効かどうか
    var hasDistance: Bool {
        distance != nil
    }

    /// 方向が有効かどうか
    var hasDirection: Bool {
        direction != nil
    }

    init(distance: Float?, direction: simd_float3?, timestamp: Date = Date()) {
        self.distance = distance
        self.direction = direction
        self.timestamp = timestamp
    }
}

// MARK: - Direction Helpers
extension NearbyMeasurement {
    /// 方向を角度（度）に変換（水平面での角度）
    var horizontalAngleDegrees: Float? {
        guard let dir = direction else { return nil }
        // x: 右が正, z: 前が負（iOSの座標系）
        let angle = atan2(dir.x, -dir.z)
        return angle * 180 / .pi
    }

    /// 方向を角度（ラジアン）に変換（水平面での角度）
    var horizontalAngleRadians: Float? {
        guard let dir = direction else { return nil }
        return atan2(dir.x, -dir.z)
    }

    /// 距離を表示用にフォーマット
    var formattedDistance: String {
        guard let dist = distance else { return "---" }
        if dist < 1.0 {
            return String(format: "%.0f cm", dist * 100)
        } else {
            return String(format: "%.2f m", dist)
        }
    }
}
