//
//  SizeCalculator.swift
//  encoder
//
//  Created by Pedro  on 4/11/23.
//

import Foundation
import MetalKit


public class SizeCalculator {

    // CRITICAL FIX: Cache last stable orientation to avoid reading unstable device orientation during render
    private static var lastStableOrientation: UIDeviceOrientation = .landscapeLeft

    public init() { }

    public static func processMatrix(initialOrientation: Int) -> CGImagePropertyOrientation {
        switch initialOrientation {
        case 90:
            return SizeCalculator.processMatrix(initialOrientation: UIDeviceOrientation.portrait)
        case 270:
            return SizeCalculator.processMatrix(initialOrientation: UIDeviceOrientation.portraitUpsideDown)
        case 0:
            return SizeCalculator.processMatrix(initialOrientation: UIDeviceOrientation.landscapeLeft)
        case 180:
            return SizeCalculator.processMatrix(initialOrientation: UIDeviceOrientation.landscapeRight)
        default:
            return SizeCalculator.processMatrix(initialOrientation: UIDeviceOrientation.landscapeLeft)
        }
    }

    /// Get stable device orientation, filtering out unstable states like faceUp, faceDown, unknown
    private static func getStableOrientation() -> UIDeviceOrientation {
        let currentOrientation = UIDevice.current.orientation

        // CRITICAL FIX: Filter out unstable orientations
        // When phone is pointed down (faceDown) or up (faceUp), iOS orientation becomes unstable
        // This causes rapid switching between orientations, creating blinking/split screen effect
        switch currentOrientation {
        case .faceUp, .faceDown, .unknown:
            // Return last known stable orientation instead of current unstable one
            return lastStableOrientation
        case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight:
            // Valid stable orientation - cache it for future use
            lastStableOrientation = currentOrientation
            return currentOrientation
        @unknown default:
            return lastStableOrientation
        }
    }

    /// Reset cached orientation (useful when app starts or orientation lock changes)
    public static func resetCachedOrientation() {
        lastStableOrientation = .landscapeLeft
    }

    /// Force a specific stable orientation (useful for orientation locking)
    public static func forceOrientation(_ orientation: UIDeviceOrientation) {
        switch orientation {
        case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight:
            lastStableOrientation = orientation
        default:
            break
        }
    }

    public static func processMatrix(initialOrientation: UIDeviceOrientation) -> CGImagePropertyOrientation {
        // CRITICAL FIX: Use stable orientation instead of directly reading UIDevice.current.orientation
        let deviceOrientation = getStableOrientation()

        switch initialOrientation {
        case .landscapeRight:
            switch deviceOrientation {
            case .landscapeLeft:
                return .up
            case .landscapeRight:
                return .down
            case .portrait:
                return .right
            case .portraitUpsideDown:
                return .left
            default:
                return .up
            }
        case .landscapeLeft:
            switch deviceOrientation {
            case .landscapeLeft:
                return .down
            case .landscapeRight:
                return .up
            case .portrait:
                return .left
            case .portraitUpsideDown:
                return .right
            default:
                return .up
            }
        case .portrait:
            switch deviceOrientation {
            case .landscapeLeft:
                return .left
            case .landscapeRight:
                return .right
            case .portrait:
                return .up
            case .portraitUpsideDown:
                return .down
            default:
                return .up
            }
        case .portraitUpsideDown:
            switch deviceOrientation {
            case .landscapeLeft:
                return .right
            case .landscapeRight:
                return .left
            case .portrait:
                return .down
            case .portraitUpsideDown:
                return .up
            default:
                return .up
            }
        default:
            return .up
        }
    }
    
    public static func getViewPort(mode: AspectRatioMode, streamWidth: CGFloat, streamHeight: CGFloat, previewWidth: CGFloat, previewHeight: CGFloat) -> MetalViewport  {
        if mode == AspectRatioMode.NONE {
            let positionX: CGFloat = 0
            let positionY: CGFloat = 0
            let scaleX = previewWidth / streamWidth
            let scaleY = previewHeight / streamHeight
            return MetalViewport(positionX: positionX, positionY: positionY, scaleX: scaleX, scaleY: scaleY)
        }
        let streamAspectRatio = streamWidth / streamHeight;
        let previewAspectRatio = previewWidth / previewHeight;
        var xo: CGFloat = 0;
        var yo: CGFloat = 0;
        var xf: CGFloat = previewWidth;
        var yf: CGFloat = previewHeight;
        if mode == AspectRatioMode.ADJUST {
            if streamAspectRatio > previewAspectRatio {
                yf = streamHeight * previewWidth / streamWidth;
                yo = (yf - previewHeight) / -2;
            } else {
                xf = streamWidth * previewHeight / streamHeight;
                xo = (xf - previewWidth) / -2;
            }
        } else { //AspectRatioMode.FILL
            if streamAspectRatio > previewAspectRatio {
                xf = streamWidth * previewHeight / streamHeight;
                xo = (xf - previewWidth) / -2;
            } else {
                yf = streamHeight * previewWidth / streamWidth;
                yo = (yf - previewHeight) / -2;
            }
        }
        let scaleX = xf / streamWidth
        let scaleY = yf / streamHeight
        return MetalViewport(positionX: xo, positionY: yo, scaleX: scaleX, scaleY: scaleY)
    }
}
