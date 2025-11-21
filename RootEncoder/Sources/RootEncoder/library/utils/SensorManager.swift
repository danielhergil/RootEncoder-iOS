//
//  SensorManager.swift
//
//
//  Created by Pedro  on 30/8/24.
//  Modified: Added orientation filtering and duplicate suppression
//

import Foundation
import UIKit

public class SensorManager {

    private var running = false
    private var lastReportedOrientation: Int = -1
    private var lastStableOrientation: UIDeviceOrientation = .unknown
    private var stabilityCounter: Int = 0
    private let stabilityThreshold: Int = 3 // Require 3 consecutive readings before changing

    public func start(callback: @escaping (Int) -> Void) {
        running = true
        DispatchQueue(label: "SensorManager").async {
            while self.running {
                DispatchQueue.main.sync {
                    let orientation = self.getStableOrientation()

                    // CRITICAL FIX: Only notify callback when orientation actually changes
                    // This prevents duplicate orientation updates that cause camera blinking
                    if orientation != self.lastReportedOrientation {
                        self.lastReportedOrientation = orientation
                        callback(orientation)
                    }
                }
                // Reduced polling frequency to save battery and reduce CPU usage
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
    }

    public func stop() {
        running = false
    }

    /// Get stable orientation with filtering for faceUp, faceDown, and unknown states
    /// Similar to Android's SensorRotationManager filtering logic
    private func getStableOrientation() -> Int {
        let currentOrientation = UIDevice.current.orientation

        // Filter out unstable orientations (faceUp, faceDown, unknown)
        let isStable: Bool
        switch currentOrientation {
        case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight:
            isStable = true
        default:
            isStable = false
        }

        if isStable {
            // Check if orientation has been stable for enough readings
            if currentOrientation == lastStableOrientation {
                stabilityCounter += 1
            } else {
                lastStableOrientation = currentOrientation
                stabilityCounter = 1
            }

            // Only accept new orientation after it's been stable for threshold readings
            if stabilityCounter >= stabilityThreshold {
                return CameraHelper.getCameraOrientation()
            }
        }

        // Return last reported orientation if current one is not stable
        return lastReportedOrientation >= 0 ? lastReportedOrientation : 0
    }

    /// Force orientation update (useful when app locks orientation)
    public func forceOrientation(_ orientation: Int) {
        lastReportedOrientation = orientation
    }
}
