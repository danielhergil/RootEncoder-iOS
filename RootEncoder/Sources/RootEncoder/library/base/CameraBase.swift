//
// Created by Pedro  on 25/9/21.
// Copyright (c) 2021 pedroSG94. All rights reserved.
//

import Foundation
import AVFoundation
import MetalKit

public class CameraBase {

    private var microphone: MicrophoneManager!
    private var cameraManager: CameraManager!
    private var audioEncoder: AudioEncoder!
    internal var videoEncoder: VideoEncoder!
    private(set) var endpoint: String = ""
    private var streaming = false
    private var onPreview = false
    private var fpsListener = FpsListener()
    private let recordController = RecordController()
    private var callback: CameraBaseCallback? = nil
    private(set) public var metalInterface: MetalInterface
    
    public init(view: MetalView) {
        self.metalInterface = view
        initialize()
    }
    
    public init() {
        self.metalInterface = MetalStreamInterface()
        initialize()
    }
    
    private func initialize() {
        let callback = createCameraBaseCallbacks()
        self.callback = callback
        cameraManager = CameraManager(callback: callback)
        microphone = MicrophoneManager(callback: callback)
        videoEncoder = VideoEncoder(callback: callback)
        audioEncoder = AudioEncoder(callback: callback)
    }

    func onAudioInfoImp(sampleRate: Int, isStereo: Bool) {}

    public func prepareAudio(bitrate: Int, sampleRate: Int, isStereo: Bool) -> Bool {
        let channels = isStereo ? 2 : 1
        recordController.setAudioFormat(sampleRate: sampleRate, channels: channels, bitrate: bitrate)
        let createResult = microphone.createMicrophone()
        if !createResult {
            return false
        }
        onAudioInfoImp(sampleRate: sampleRate, isStereo: isStereo)
        return audioEncoder.prepareAudio(sampleRate: Double(sampleRate), channels: isStereo ? 2 : 1, bitrate: bitrate)
    }

    public func prepareAudio() -> Bool {
        prepareAudio(bitrate: 128 * 1000, sampleRate: 32000, isStereo: true)
    }

    public func prepareVideo(width: Int, height: Int, fps: Int, bitrate: Int, iFrameInterval: Int = 2, rotation: Int = CameraHelper.getCameraOrientation()) -> Bool {
        var w = width
        var h = height
        if (rotation == 90 || rotation == 270) {
            w = height
            h = width
        }
        var shouldStartPreview = false
        if onPreview {
            let size = metalInterface.getEncoderSize()
            if size.width != CGFloat(w) || size.height != CGFloat(h) {
                stopPreview()
                shouldStartPreview = true
            }
        }
        if !cameraManager.prepare(width: width, height: height, fps: 30, rotation: rotation) {
            return false
        }
        if !cameraManager.running {
            cameraManager.start()
            if shouldStartPreview {
                onPreview = true
            }
        }
        metalInterface.setForceFps(fps: fps)
        metalInterface.setEncoderSize(width: w, height: h)
        metalInterface.setOrientation(orientation: rotation)
        recordController.setVideoFormat(witdh: w, height: h, bitrate: bitrate)
        return videoEncoder.prepareVideo(width: width, height: height, fps: fps, bitrate: bitrate, iFrameInterval: iFrameInterval, rotation: rotation)
    }

    public func prepareVideo() -> Bool {
        prepareVideo(width: 640, height: 480, fps: 30, bitrate: 1200 * 1000)
    }

    public func setFpsListener(fpsCallback: FpsCallback) {
        fpsListener.setCallback(callback: fpsCallback)
    }

    func startStreamImp(endpoint: String) {}
        
    public func startStream(endpoint: String) {
        self.endpoint = endpoint
        if (!isRecording()) {
            startEncoders()
        }
        onPreview = true
        streaming = true
        startStreamImp(endpoint: endpoint)
    }

    private func startEncoders() {
        audioEncoder.start()
        videoEncoder.start()
        microphone.start()
        cameraManager.start()
        metalInterface.setCallback(callback: callback)
    }
    
    private func stopEncoders() {
        metalInterface.setCallback(callback: nil)
        microphone.stop()
        audioEncoder.stop()
        videoEncoder.stop()
    }
    
    func stopStreamImp() {}

    public func stopStream() {
        if (!isRecording()) {
            stopEncoders()
        }
        stopStreamImp()
        endpoint = ""
        streaming = false
    }
    
    public func startRecord(path: URL) {
        recordController.startRecord(path: path)
        if (!streaming) {
            startEncoders()
        }
    }

    public func stopRecord() {
        if (!streaming) {
            stopEncoders()
        }
        recordController.stopRecord()
    }
    
    public func isRecording() -> Bool {
        return recordController.isRecording()
    }
    
    public func isStreaming() -> Bool {
        streaming
    }

    public func isOnPreview() -> Bool {
        onPreview
    }

    public func switchCamera() {
        cameraManager.switchCamera()
    }
    
    public func enableLantern() {
      cameraManager.setTorch(isOn: true);
    }

    public func disableLantern() {
      cameraManager.setTorch(isOn: false);
    }

    public func isLanternEnabled() -> Bool {
      return cameraManager.isTorchEnabled();
    }
    
    public func setZoom(level: CGFloat) {
        return cameraManager.setZoom(level: level)
    }
    
    public func getZoom() -> CGFloat {
        return cameraManager.getZoom()
    }
    
    public func getMinZoom() -> CGFloat {
        return cameraManager.getMinZoom()
    }
    
    public func getMaxZoom() -> CGFloat {
        return cameraManager.getMaxZoom()
    }
    
    public func isMuted() -> Bool {
        return microphone.isMuted()
    }
    
    public func mute() {
        microphone.mute()
    }
    
    public func unmute() {
        microphone.unmute()
    }
    
    public func getCameraManager() -> CameraManager {
        cameraManager
    }

    // MARK: - Manual Camera Controls

    // MARK: ISO Control

    /// Set manual ISO value
    /// - Parameter iso: ISO value (will be clamped to device range)
    /// - Returns: true if successful, false if not supported or device unavailable
    public func setManualISO(_ iso: Float) -> Bool {
        return cameraManager.setManualISO(iso)
    }

    /// Get current ISO value
    /// - Returns: Current ISO value
    public func getISO() -> Float {
        return cameraManager.getISO()
    }

    /// Get minimum supported ISO value
    /// - Returns: Minimum ISO value
    public func getMinISO() -> Float {
        return cameraManager.getMinISO()
    }

    /// Get maximum supported ISO value
    /// - Returns: Maximum ISO value
    public func getMaxISO() -> Float {
        return cameraManager.getMaxISO()
    }

    /// Enable automatic ISO
    /// - Returns: true if successful, false if not supported
    public func enableAutoISO() -> Bool {
        return cameraManager.enableAutoISO()
    }

    /// Check if ISO is in automatic mode
    /// - Returns: true if auto ISO is enabled
    public func isAutoISO() -> Bool {
        return cameraManager.isAutoISO()
    }

    // MARK: Exposure Time Control

    /// Set manual exposure time
    /// - Parameter duration: Exposure duration as CMTime (will be clamped to device range)
    /// - Returns: true if successful, false if not supported
    public func setManualExposureTime(_ duration: CMTime) -> Bool {
        return cameraManager.setManualExposureTime(duration)
    }

    /// Set manual exposure time using shutter speed notation (e.g., 1/60, 1/125)
    /// - Parameters:
    ///   - numerator: Numerator of the fraction (usually 1)
    ///   - denominator: Denominator of the fraction (e.g., 60 for 1/60 second)
    /// - Returns: true if successful, false if not supported
    public func setManualExposureTimeShutter(numerator: Int32, denominator: Int32) -> Bool {
        return cameraManager.setManualExposureTimeShutter(numerator: numerator, denominator: denominator)
    }

    /// Get current exposure time
    /// - Returns: Current exposure duration as CMTime
    public func getExposureTime() -> CMTime {
        return cameraManager.getExposureTime()
    }

    /// Get current exposure time in seconds
    /// - Returns: Current exposure duration in seconds
    public func getExposureTimeSeconds() -> Double {
        return cameraManager.getExposureTimeSeconds()
    }

    /// Get minimum supported exposure time
    /// - Returns: Minimum exposure duration as CMTime
    public func getMinExposureTime() -> CMTime {
        return cameraManager.getMinExposureTime()
    }

    /// Get maximum supported exposure time
    /// - Returns: Maximum exposure duration as CMTime
    public func getMaxExposureTime() -> CMTime {
        return cameraManager.getMaxExposureTime()
    }

    // MARK: White Balance Control

    /// Set white balance by color temperature in Kelvin
    /// - Parameter kelvin: Color temperature in Kelvin (typically 2000-8000K, will be clamped)
    /// - Returns: true if successful, false if not supported
    public func setWhiteBalanceTemperature(_ kelvin: Float) -> Bool {
        return cameraManager.setWhiteBalanceTemperature(kelvin)
    }

    /// Set white balance using RGB gains
    /// - Parameters:
    ///   - redGain: Red channel gain (1.0 = neutral)
    ///   - greenGain: Green channel gain (1.0 = neutral)
    ///   - blueGain: Blue channel gain (1.0 = neutral)
    /// - Returns: true if successful, false if not supported
    public func setWhiteBalanceGains(redGain: Float, greenGain: Float, blueGain: Float) -> Bool {
        return cameraManager.setWhiteBalanceGains(redGain: redGain, greenGain: greenGain, blueGain: blueGain)
    }

    /// Enable automatic white balance
    /// - Returns: true if successful, false if not supported
    public func enableAutoWhiteBalance() -> Bool {
        return cameraManager.enableAutoWhiteBalance()
    }

    /// Check if white balance is in automatic mode
    /// - Returns: true if auto white balance is enabled
    public func isAutoWhiteBalance() -> Bool {
        return cameraManager.isAutoWhiteBalance()
    }

    /// Get current white balance gains
    /// - Returns: Current white balance gains (red, green, blue)
    public func getWhiteBalanceGains() -> AVCaptureDevice.WhiteBalanceGains {
        return cameraManager.getWhiteBalanceGains()
    }

    /// Get current white balance as color temperature in Kelvin
    /// - Returns: Color temperature in Kelvin
    public func getWhiteBalanceTemperature() -> Float {
        return cameraManager.getWhiteBalanceTemperature()
    }

    /// Get maximum allowed white balance gain
    /// - Returns: Maximum gain value
    public func getMaxWhiteBalanceGain() -> Float {
        return cameraManager.getMaxWhiteBalanceGain()
    }

    // MARK: Exposure Compensation Control

    /// Set exposure compensation (EV)
    /// - Parameter ev: Exposure compensation in EV units (will be clamped to device range)
    /// - Returns: true if successful, false if device unavailable
    public func setExposureCompensation(_ ev: Float) -> Bool {
        return cameraManager.setExposureCompensation(ev)
    }

    /// Get current exposure compensation value
    /// - Returns: Current exposure compensation in EV units
    public func getExposureCompensation() -> Float {
        return cameraManager.getExposureCompensation()
    }

    /// Get minimum supported exposure compensation
    /// - Returns: Minimum EV value
    public func getMinExposureCompensation() -> Float {
        return cameraManager.getMinExposureCompensation()
    }

    /// Get maximum supported exposure compensation
    /// - Returns: Maximum EV value
    public func getMaxExposureCompensation() -> Float {
        return cameraManager.getMaxExposureCompensation()
    }

    /// Reset exposure compensation to 0 EV
    /// - Returns: true if successful
    public func resetExposureCompensation() -> Bool {
        return cameraManager.resetExposureCompensation()
    }

    // MARK: Focus Distance Control

    /// Set manual focus distance
    /// - Parameter lensPosition: Focus distance (0.0 = infinity, 1.0 = minimum focus distance)
    /// - Returns: true if successful, false if not supported
    public func setManualFocus(_ lensPosition: Float) -> Bool {
        return cameraManager.setManualFocus(lensPosition)
    }

    /// Enable automatic focus
    /// - Returns: true if successful, false if not supported
    public func enableAutoFocus() -> Bool {
        return cameraManager.enableAutoFocus()
    }

    /// Check if focus is in automatic mode
    /// - Returns: true if auto focus is enabled
    public func isAutoFocus() -> Bool {
        return cameraManager.isAutoFocus()
    }

    /// Get current lens position (focus distance)
    /// - Returns: Current lens position (0.0 = infinity, 1.0 = minimum focus distance)
    public func getLensPosition() -> Float {
        return cameraManager.getLensPosition()
    }

    /// Lock camera orientation to prevent video rotation when device rotates
    /// This prevents blinking and rotation when device moves
    public func lockOrientation() {
        metalInterface.lockOrientation()
    }

    /// Unlock camera orientation to allow video rotation when device rotates
    public func unlockOrientation() {
        metalInterface.unlockOrientation()
    }

    public func replaceMetalInterface() {
        self.metalInterface.setCallback(callback: nil)
        let metalStreamInterface = MetalStreamInterface()
        metalStreamInterface.setForceFps(fps: videoEncoder.fps)
        var w = videoEncoder.width
        var h = videoEncoder.height
        if (videoEncoder.rotation == 90 || videoEncoder.rotation == 270) {
            w = videoEncoder.height
            h = videoEncoder.width
        }
        metalStreamInterface.setEncoderSize(width: w, height: h)
        metalStreamInterface.setOrientation(orientation: videoEncoder.rotation)
        metalStreamInterface.setCallback(callback: callback)
        metalInterface = metalStreamInterface
    }
    
    public func replaceMetalInterface(metalView: MetalView) {
        self.metalInterface.setCallback(callback: nil)
        metalView.setForceFps(fps: videoEncoder.fps)
        var w = videoEncoder.width
        var h = videoEncoder.height
        if (videoEncoder.rotation == 90 || videoEncoder.rotation == 270) {
            w = videoEncoder.height
            h = videoEncoder.width
        }
        metalView.setEncoderSize(width: w, height: h)
        metalView.setOrientation(orientation: videoEncoder.rotation)
        metalView.setCallback(callback: callback)
        metalInterface = metalView
    }
    
    public func setVideoBitrateOnFly(bitrate: Int) {
        videoEncoder.setVideoBitrateOnFly(bitrate: bitrate)
    }
    /**
     * Get supported resolutions of back camera in px.
     *
     * @return list of resolutions supported by back camera
     */
    public func getResolutionsBack() -> [CMVideoDimensions] {
      return cameraManager.getBackCameraResolutions()
    }

    /**
     * Get supported resolutions of front camera in px.
     *
     * @return list of resolutions supported by front camera
     */
    public func getResolutionsFront() -> [CMVideoDimensions] {
      return cameraManager.getFrontCameraResolutions()
    }

    @discardableResult
    public func startPreview(width: Int = 640, height: Int = 480, facing: CameraHelper.Facing = .BACK, rotation: Int = CameraHelper.getCameraOrientation()) -> Bool {
        if (!isOnPreview()) {
            var w = width
            var h = height
            if (rotation == 90 || rotation == 270) {
                w = height
                h = width
            }
            if !cameraManager.prepare(width: width, height: height, fps: 30, rotation: rotation, facing: facing) {
                fatalError("Camera resolution not supported")
            }
            metalInterface.setEncoderSize(width: w, height: h)
            metalInterface.setOrientation(orientation: rotation)
            cameraManager.start()
            onPreview = true
            return true
        }
        return false
    }

    public func stopPreview() {
        if (!isStreaming() && isOnPreview()) {
            cameraManager.stop()
            onPreview = false
        }
    }
    
    public func setVideoCodec(codec: VideoCodec) {
        setVideoCodecImp(codec: codec)
        recordController.setVideoCodec(codec: codec)
        videoEncoder.setCodec(codec: codec)
    }
    
    public func setAudioCodec(codec: AudioCodec) {
        setAudioCodecImp(codec: codec)
        recordController.setAudioCodec(codec: codec)
        audioEncoder.setCodec(codec: codec)
    }

    func setVideoCodecImp(codec: VideoCodec) {}
    
    func setAudioCodecImp(codec: AudioCodec) {}
    
    func getAudioDataImp(frame: Frame) {}

    func onVideoInfoImp(sps: Array<UInt8>, pps: Array<UInt8>, vps: Array<UInt8>?) {}

    func getVideoDataImp(frame: Frame) {}
}

protocol CameraBaseCallback: GetMicrophoneData, GetCameraData, GetAudioData, GetVideoData, MetalViewCallback {}

extension CameraBase {
    func createCameraBaseCallbacks() -> CameraBaseCallback {
        class CameraBaseCallbackHandler: CameraBaseCallback {
            
            private let cameraBase: CameraBase
            
            init(cameraBase: CameraBase) {
                self.cameraBase = cameraBase
            }
            
            func getPcmData(frame: PcmFrame) {
                cameraBase.recordController.recordAudio(pcmBuffer: frame.buffer, time: frame.time)
                cameraBase.audioEncoder.encodeFrame(frame: frame)
            }

            func getYUVData(from buffer: CMSampleBuffer) {
                cameraBase.metalInterface.sendBuffer(buffer: buffer)
            }

            func getVideoData(pixelBuffer: CVPixelBuffer, pts: CMTime) {
                cameraBase.recordController.recordVideo(pixelBuffer: pixelBuffer, pts: pts)
                cameraBase.videoEncoder.encodeFrame(pixelBuffer: pixelBuffer, pts: pts)
            }
            
            func getAudioData(frame: Frame) {
                cameraBase.getAudioDataImp(frame: frame)
            }

            func getVideoData(frame: Frame) {
                cameraBase.fpsListener.calculateFps()
                cameraBase.getVideoDataImp(frame: frame)
            }

            func onVideoInfo(sps: Array<UInt8>, pps: Array<UInt8>, vps: Array<UInt8>?) {
                cameraBase.onVideoInfoImp(sps: sps, pps: pps, vps: vps)
            }
        }
        return CameraBaseCallbackHandler(cameraBase: self)
    }
}
