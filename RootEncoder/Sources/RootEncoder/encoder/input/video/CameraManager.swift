//
//  CameraManager.swift
//  app
//
//  Created by Pedro on 13/09/2020.
//  Copyright © 2020 pedroSG94. All rights reserved.
//

import UIKit
import Foundation
import AVFoundation

public class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    private let thread = DispatchQueue(label: "CameraManager")
    var session: AVCaptureSession?
    var device: AVCaptureDevice?
    var input: AVCaptureDeviceInput?
    var output: AVCaptureVideoDataOutput?
    var prevLayer: AVCaptureVideoPreviewLayer?
    var videoOutput: AVCaptureVideoDataOutput?
    private var fpsLimiter = FpsLimiter()

    private var facing = CameraHelper.Facing.BACK
    private var width: Int = 640
    private var height: Int = 480
    private var resolution = CameraHelper.Resolution.vga640x480
    public var rotation: Int = 0
    private(set) var running = false
    private var callback: GetCameraData
    private var prepared = false
    
    public init(callback: GetCameraData) {
        self.callback = callback
    }

    public func stop() {
        prevLayer?.removeFromSuperlayer()
        prevLayer = nil
        session?.stopRunning()
        session?.removeOutput(output!)
        session?.removeInput(input!)
        running = false
    }

    public func prepare(width: Int, height: Int, fps: Int, rotation: Int, facing: CameraHelper.Facing = .BACK) -> Bool {
        let resolutions = facing == .BACK ? getBackCameraResolutions() : getFrontCameraResolutions()
        guard let lowerResolution = resolutions.first else { return false }
        guard let higherResolution = resolutions.last else { return false }
        if width < lowerResolution.width || height < lowerResolution.height { return false }
        if width > higherResolution.width || height > higherResolution.height { return false }
        do {
            let resolution = try CameraHelper.Resolution.getOptimalResolution(width: width, height: height)
            self.width = width
            self.height = height
            self.resolution = resolution
            fpsLimiter.setFps(fps: fps)
            self.rotation = rotation
            self.facing = facing
            prepared = true
            return true
        } catch {
            return false
        }
    }

    public func start() {
        start(width: width, height: height, facing: facing, rotation: rotation)
    }

    public func start(width: Int, height: Int) {
        start(width: width, height: width, facing: facing, rotation: rotation)
    }

    public func switchCamera() {
        if (facing == .FRONT) {
            facing = .BACK
        } else if (facing == .BACK) {
            facing = .FRONT
        }
        if (running) {
            stop()
            start(width: width, height: height, facing: facing, rotation: rotation)
        }
    }
    
    @discardableResult
    public func setTorch(isOn: Bool) -> Bool {
        guard let device, device.hasTorch else {
            return false
        }
        do {
            let torchMode: AVCaptureDevice.TorchMode = isOn ? .on : .off
            try device.lockForConfiguration()
            if device.isTorchModeSupported(torchMode) {
                device.torchMode = torchMode
            }
            device.unlockForConfiguration()
            return true
        } catch {
            return false
        }
    }
    
    public func isTorchEnabled() -> Bool {
        guard let device, device.hasTorch else {
            return false
        }
        return device.isTorchActive
    }
    
    public func setZoom(level: CGFloat) {
        guard let device else { return }
        if level < getMinZoom() {
            setZoom(level: getMinZoom())
            return
        }
        if level > getMaxZoom() {
            setZoom(level: getMaxZoom())
            return
        }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = level
            device.unlockForConfiguration()
        } catch { }
    }
    
    public func getZoom() -> CGFloat {
        guard let device else { return 0 }
        return device.videoZoomFactor
    }
    
    public func getMinZoom() -> CGFloat {
        guard let device else { return 0 }
        return device.minAvailableVideoZoomFactor
    }
    
    public func getMaxZoom() -> CGFloat {
        guard let device else { return 0 }
        return device.maxAvailableVideoZoomFactor
    }
    
    public func getBackCameraResolutions() -> [CMVideoDimensions] {
        return getResolutionsByFace(facing: .BACK)
    }
    
    public func getFrontCameraResolutions() -> [CMVideoDimensions] {
        return getResolutionsByFace(facing: .FRONT)
    }
    
    public func getResolutionsByFace(facing: CameraHelper.Facing) -> [CMVideoDimensions] {
        let position = facing == CameraHelper.Facing.BACK ? AVCaptureDevice.Position.back : AVCaptureDevice.Position.front
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: position)

        // Check if devices array is empty (simulator case)
        guard !devices.devices.isEmpty else {
            print("Warning: No camera devices found (running in simulator?)")
            return []
        }

        let device = devices.devices[0]
        let descriptions = device.formats.map(\.formatDescription)
        let sizes = descriptions.map(\.dimensions)
        var resolutions = [CMVideoDimensions]()
        for size in sizes {
            var exists = false
            for r in resolutions {
                if r.width == size.width && r.height == size.height
                    //Currently the higher preset is 3840x2160
                    //More than 3840 width or 2160 height is not allowed because this need rescale producing bad image quality.
                    || size.height > 2160 || size.width > 3840 {
                    exists = true
                    break
                }
            }
            if !exists {
                resolutions.append(size)
            }
        }
        return resolutions.sorted(by: { $0.height < $1.height })
    }
    
    public func start(width: Int, height: Int, facing: CameraHelper.Facing, rotation: Int) {
        if !prepared {
            fatalError("CameraManager not prepared")
        }
        self.facing = facing
        if (running) {
            if (width != self.width || height != self.height || rotation != self.rotation) {
                stop()
            } else {
                return
            }
        }
        self.rotation = rotation
        session = AVCaptureSession()
        session?.sessionPreset = self.resolution.preset
        let position = facing == CameraHelper.Facing.BACK ? AVCaptureDevice.Position.back : AVCaptureDevice.Position.front
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: position)

        // Check if devices array is empty (simulator case)
        guard !devices.devices.isEmpty else {
            print("Error: Cannot start camera - no devices found (running in simulator?)")
            return
        }

        device = devices.devices[0]

        do{
            input = try AVCaptureDeviceInput(device: device!)
        } catch {
            print(error)
        }

        if let input = input{
            session?.addInput(input)
        }

        output = AVCaptureVideoDataOutput()
        output?.setSampleBufferDelegate(self, queue: thread)
        output?.alwaysDiscardsLateVideoFrames = true
        output?.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)]

        session?.addOutput(output!)
        output?.connections.filter { $0.isVideoOrientationSupported }.forEach {
            $0.videoOrientation = getOrientation(value: rotation)
        }
        session?.commitConfiguration()
        thread.async {
            self.session?.startRunning()
        }
        running = true
    }
    
    public func cameraWithPosition(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera, .builtInTelephotoCamera, .builtInTrueDepthCamera, .builtInWideAngleCamera, ], mediaType: .video, position: position)

        if let device = deviceDiscoverySession.devices.first {
            return device
        }
        return nil
    }
    
    private func transformOrientation(orientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        switch orientation {
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return .portrait
        }
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if !fpsLimiter.limitFps() {
            self.callback.getYUVData(from: sampleBuffer)
        }
    }
    
    private func getOrientation(value: Int) -> AVCaptureVideoOrientation {
        switch value {
        case 90:
            return .portrait
        case 270:
            return .portraitUpsideDown
        case 0:
            return .landscapeLeft
        case 180:
            return .landscapeRight
        default:
            return .landscapeLeft
        }
    }
    
    public func getCaptureSession() -> AVCaptureSession? {
        session
    }

    // MARK: - Manual ISO Control

    /// Set manual ISO value
    /// - Parameter iso: ISO value to set (will be clamped to device range)
    /// - Returns: true if successful, false otherwise
    public func setManualISO(_ iso: Float) -> Bool {
        guard let device else { return false }
        guard device.isExposureModeSupported(.custom) else {
            print("Manual ISO not supported on this device")
            return false
        }

        let minISO = device.activeFormat.minISO
        let maxISO = device.activeFormat.maxISO
        let clampedISO = min(max(iso, minISO), maxISO)

        do {
            try device.lockForConfiguration()
            // Keep current exposure duration, only change ISO
            device.setExposureModeCustom(
                duration: device.exposureDuration,
                iso: clampedISO
            ) { (time) in
                print("Manual ISO \(clampedISO) applied at time: \(time)")
            }
            device.unlockForConfiguration()
            return true
        } catch {
            print("Error setting manual ISO: \(error)")
            return false
        }
    }

    /// Get current ISO value
    /// - Returns: Current ISO value
    public func getISO() -> Float {
        guard let device else { return 0 }
        return device.iso
    }

    /// Get minimum supported ISO value
    /// - Returns: Minimum ISO value
    public func getMinISO() -> Float {
        guard let device else { return 0 }
        return device.activeFormat.minISO
    }

    /// Get maximum supported ISO value
    /// - Returns: Maximum ISO value
    public func getMaxISO() -> Float {
        guard let device else { return 0 }
        return device.activeFormat.maxISO
    }

    /// Enable automatic ISO (auto exposure)
    /// - Returns: true if successful, false otherwise
    public func enableAutoISO() -> Bool {
        guard let device else { return false }
        guard device.isExposureModeSupported(.continuousAutoExposure) else { return false }

        do {
            try device.lockForConfiguration()
            device.exposureMode = .continuousAutoExposure
            device.unlockForConfiguration()
            print("Auto ISO enabled")
            return true
        } catch {
            print("Error enabling auto ISO: \(error)")
            return false
        }
    }

    /// Check if auto ISO is currently enabled
    /// - Returns: true if auto exposure is enabled
    public func isAutoISO() -> Bool {
        guard let device else { return false }
        return device.exposureMode == .continuousAutoExposure || device.exposureMode == .autoExpose
    }

    // MARK: - Manual Exposure Time Control

    /// Set manual exposure time (shutter speed)
    /// - Parameter duration: Exposure duration as CMTime
    /// - Returns: true if successful, false otherwise
    public func setManualExposureTime(_ duration: CMTime) -> Bool {
        guard let device else { return false }
        guard device.isExposureModeSupported(.custom) else {
            print("Manual exposure time not supported on this device")
            return false
        }

        let minDuration = device.activeFormat.minExposureDuration
        let maxDuration = device.activeFormat.maxExposureDuration
        let clampedDuration = CMTimeClamp(duration, min: minDuration, max: maxDuration)

        do {
            try device.lockForConfiguration()
            // Keep current ISO, only change exposure time
            device.setExposureModeCustom(
                duration: clampedDuration,
                iso: device.iso
            ) { (time) in
                print("Manual exposure time applied at time: \(time)")
            }
            device.unlockForConfiguration()
            return true
        } catch {
            print("Error setting manual exposure time: \(error)")
            return false
        }
    }

    /// Set manual exposure time using shutter speed fraction (e.g., 1/30 for 30fps)
    /// - Parameters:
    ///   - numerator: Numerator of the fraction (typically 1)
    ///   - denominator: Denominator of the fraction (e.g., 30 for 1/30s)
    /// - Returns: true if successful, false otherwise
    public func setManualExposureTimeShutter(numerator: Int64, denominator: Int32) -> Bool {
        let duration = CMTimeMake(value: numerator, timescale: denominator)
        return setManualExposureTime(duration)
    }

    /// Get current exposure time
    /// - Returns: Current exposure duration as CMTime
    public func getExposureTime() -> CMTime {
        guard let device else { return .zero }
        return device.exposureDuration
    }

    /// Get current exposure time as seconds
    /// - Returns: Exposure time in seconds
    public func getExposureTimeSeconds() -> Double {
        let time = getExposureTime()
        return CMTimeGetSeconds(time)
    }

    /// Get minimum supported exposure time
    /// - Returns: Minimum exposure duration
    public func getMinExposureTime() -> CMTime {
        guard let device else { return .zero }
        return device.activeFormat.minExposureDuration
    }

    /// Get maximum supported exposure time
    /// - Returns: Maximum exposure duration
    public func getMaxExposureTime() -> CMTime {
        guard let device else { return .zero }
        return device.activeFormat.maxExposureDuration
    }

    // MARK: - White Balance Control

    /// Set white balance using temperature in Kelvin
    /// - Parameter kelvin: Color temperature (2000K - 8000K typical)
    /// - Returns: true if successful, false otherwise
    public func setWhiteBalanceTemperature(_ kelvin: Float) -> Bool {
        guard let device else { return false }
        guard device.isWhiteBalanceModeSupported(.locked) else {
            print("Manual white balance not supported on this device")
            return false
        }

        let temperatureAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
            temperature: kelvin,
            tint: 0
        )

        // Convert temperature to RGB gains
        var gains = device.deviceWhiteBalanceGains(for: temperatureAndTint)

        // Clamp to device limits
        let maxGain = device.maxWhiteBalanceGain
        gains.redGain = min(max(gains.redGain, 1.0), maxGain)
        gains.greenGain = min(max(gains.greenGain, 1.0), maxGain)
        gains.blueGain = min(max(gains.blueGain, 1.0), maxGain)

        do {
            try device.lockForConfiguration()
            device.setWhiteBalanceModeLocked(with: gains) { (time) in
                print("White balance temperature \(kelvin)K applied at time: \(time)")
            }
            device.unlockForConfiguration()
            return true
        } catch {
            print("Error setting white balance temperature: \(error)")
            return false
        }
    }

    /// Set white balance using RGB gains directly
    /// - Parameters:
    ///   - redGain: Red channel gain
    ///   - greenGain: Green channel gain
    ///   - blueGain: Blue channel gain
    /// - Returns: true if successful, false otherwise
    public func setWhiteBalanceGains(redGain: Float, greenGain: Float, blueGain: Float) -> Bool {
        guard let device else { return false }
        guard device.isWhiteBalanceModeSupported(.locked) else {
            print("Manual white balance not supported on this device")
            return false
        }

        // Clamp to device limits
        let maxGain = device.maxWhiteBalanceGain
        let gains = AVCaptureDevice.WhiteBalanceGains(
            redGain: min(max(redGain, 1.0), maxGain),
            greenGain: min(max(greenGain, 1.0), maxGain),
            blueGain: min(max(blueGain, 1.0), maxGain)
        )

        do {
            try device.lockForConfiguration()
            device.setWhiteBalanceModeLocked(with: gains) { (time) in
                print("White balance gains applied at time: \(time)")
            }
            device.unlockForConfiguration()
            return true
        } catch {
            print("Error setting white balance gains: \(error)")
            return false
        }
    }

    /// Enable automatic white balance
    /// - Returns: true if successful, false otherwise
    public func enableAutoWhiteBalance() -> Bool {
        guard let device else { return false }
        guard device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) else { return false }

        do {
            try device.lockForConfiguration()
            device.whiteBalanceMode = .continuousAutoWhiteBalance
            device.unlockForConfiguration()
            print("Auto white balance enabled")
            return true
        } catch {
            print("Error enabling auto white balance: \(error)")
            return false
        }
    }

    /// Check if auto white balance is currently enabled
    /// - Returns: true if auto white balance is enabled
    public func isAutoWhiteBalance() -> Bool {
        guard let device else { return false }
        return device.whiteBalanceMode == .continuousAutoWhiteBalance
    }

    /// Get current white balance gains
    /// - Returns: Current white balance gains
    public func getWhiteBalanceGains() -> AVCaptureDevice.WhiteBalanceGains {
        guard let device else {
            return AVCaptureDevice.WhiteBalanceGains(redGain: 1.0, greenGain: 1.0, blueGain: 1.0)
        }
        return device.deviceWhiteBalanceGains
    }

    /// Get current white balance temperature
    /// - Returns: Current temperature in Kelvin
    public func getWhiteBalanceTemperature() -> Float {
        guard let device else { return 0 }
        let gains = device.deviceWhiteBalanceGains
        let temperatureAndTint = device.temperatureAndTintValues(for: gains)
        return temperatureAndTint.temperature
    }

    /// Get maximum white balance gain supported by device
    /// - Returns: Maximum gain value
    public func getMaxWhiteBalanceGain() -> Float {
        guard let device else { return 0 }
        return device.maxWhiteBalanceGain
    }

    // MARK: - Exposure Compensation Control

    /// Set exposure compensation (EV adjustment)
    /// - Parameter ev: Exposure value adjustment (typically -8.0 to +8.0)
    /// - Returns: true if successful, false otherwise
    public func setExposureCompensation(_ ev: Float) -> Bool {
        guard let device else { return false }

        let minEV = device.minExposureTargetBias
        let maxEV = device.maxExposureTargetBias
        let clampedEV = min(max(ev, minEV), maxEV)

        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(clampedEV) { (time) in
                print("Exposure compensation \(clampedEV) EV applied at time: \(time)")
            }
            device.unlockForConfiguration()
            return true
        } catch {
            print("Error setting exposure compensation: \(error)")
            return false
        }
    }

    /// Get current exposure compensation value
    /// - Returns: Current EV compensation
    public func getExposureCompensation() -> Float {
        guard let device else { return 0 }
        return device.exposureTargetBias
    }

    /// Get minimum exposure compensation supported
    /// - Returns: Minimum EV value
    public func getMinExposureCompensation() -> Float {
        guard let device else { return 0 }
        return device.minExposureTargetBias
    }

    /// Get maximum exposure compensation supported
    /// - Returns: Maximum EV value
    public func getMaxExposureCompensation() -> Float {
        guard let device else { return 0 }
        return device.maxExposureTargetBias
    }

    /// Reset exposure compensation to 0
    /// - Returns: true if successful
    public func resetExposureCompensation() -> Bool {
        return setExposureCompensation(0.0)
    }

    // MARK: - Focus Distance Control

    /// Set manual focus distance
    /// - Parameter lensPosition: Focus position (0.0 = infinity, 1.0 = closest)
    /// - Returns: true if successful, false otherwise
    public func setManualFocus(_ lensPosition: Float) -> Bool {
        guard let device else { return false }
        guard device.isFocusModeSupported(.locked) else {
            print("Manual focus not supported on this device")
            return false
        }

        let clampedPosition = min(max(lensPosition, 0.0), 1.0)

        do {
            try device.lockForConfiguration()
            device.setFocusModeLocked(lensPosition: clampedPosition) { (time) in
                print("Manual focus position \(clampedPosition) applied at time: \(time)")
            }
            device.unlockForConfiguration()
            return true
        } catch {
            print("Error setting manual focus: \(error)")
            return false
        }
    }

    /// Enable automatic focus
    /// - Returns: true if successful, false otherwise
    public func enableAutoFocus() -> Bool {
        guard let device else { return false }
        guard device.isFocusModeSupported(.continuousAutoFocus) else { return false }

        do {
            try device.lockForConfiguration()
            device.focusMode = .continuousAutoFocus
            device.unlockForConfiguration()
            print("Auto focus enabled")
            return true
        } catch {
            print("Error enabling auto focus: \(error)")
            return false
        }
    }

    /// Check if auto focus is currently enabled
    /// - Returns: true if auto focus is enabled
    public func isAutoFocus() -> Bool {
        guard let device else { return false }
        return device.focusMode == .continuousAutoFocus || device.focusMode == .autoFocus
    }

    /// Get current lens position
    /// - Returns: Current lens position (0.0 to 1.0)
    public func getLensPosition() -> Float {
        guard let device else { return 0 }
        return device.lensPosition
    }
}

