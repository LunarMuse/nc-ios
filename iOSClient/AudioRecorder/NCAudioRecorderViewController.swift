// SPDX-FileCopyrightText: Nextcloud GmbH
// SPDX-FileCopyrightText: 2019 Marino Faggiana
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  --------------------------------
//  Based on code of Venkat Kukunuru
//  --------------------------------

import UIKit
import AVFoundation
import QuartzCore
import NextcloudKit

class NCAudioRecorderViewController: UIViewController, NCAudioRecorderDelegate {
    @IBOutlet weak var contentContainerView: UIView!
    @IBOutlet weak var durationLabel: UILabel!
    @IBOutlet weak var startStopLabel: UILabel!
    @IBOutlet weak var voiceRecordHUD: VoiceRecordHUD!

    var recording: NCAudioRecorder!
    var startDate: Date = Date()
    var fileName: String = ""
    var controller: NCMainTabBarController!
    let database = NCManageDatabase.shared
    var session: NCSession.Session {
        NCSession.shared.getSession(controller: controller)
    }

    // MARK: - View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        voiceRecordHUD.update(0.0)
        durationLabel.text = ""
        startStopLabel.text = NSLocalizedString("_wait_", comment: "")

        view.backgroundColor = .clear
        contentContainerView.backgroundColor = UIColor.lightGray
        voiceRecordHUD.fillColor = UIColor.green

        Task {
            self.fileName = await NCNetworking.shared.createFileName(fileNameBase: NSLocalizedString("_untitled_", comment: "") + ".m4a", account: self.session.account, serverUrl: controller.currentServerUrl())
            recording = NCAudioRecorder(to: self.fileName)
            recording.delegate = self
            do {
                try self.recording.prepare()
                startStopLabel.text = NSLocalizedString("_voice_memo_start_", comment: "")
            } catch {
                print(error)
            }
        }
    }

    // MARK: - Action

    @IBAction func touchViewController() {
        if recording.state == .record {
            startStop()
        } else {
            dismiss(animated: true)
        }
    }

    @IBAction func startStop() {
        if recording.state == .record {
            recording.stop()
            voiceRecordHUD.update(0.0)
            dismiss(animated: true) {
                self.uploadMetadata()
            }
        } else {
            do {
                try recording.record()
                startDate = Date()
                startStopLabel.text = NSLocalizedString("_voice_memo_stop_", comment: "")
            } catch {
                print(error)
            }
        }
    }

    func uploadMetadata() {
        Task {
            let fileNamePath = NSTemporaryDirectory() + self.fileName
            let metadata = await NCManageDatabase.shared.createMetadataAsync(fileName: fileName,
                                                                             ocId: UUID().uuidString,
                                                                             serverUrl: controller.currentServerUrl(),
                                                                             session: self.session,
                                                                             sceneIdentifier: self.controller?.sceneIdentifier)

            metadata.session = NCNetworking.shared.sessionUploadBackground
            metadata.sessionSelector = NCGlobal.shared.selectorUploadFile
            metadata.status = NCGlobal.shared.metadataStatusWaitUpload
            metadata.sessionDate = Date()
            metadata.size = NCUtilityFileSystem().getFileSize(filePath: fileNamePath)
            NCUtilityFileSystem().copyFile(atPath: fileNamePath, toPath: NCUtilityFileSystem().getDirectoryProviderStorageOcId(metadata.ocId,
                                                                                                                               fileName: metadata.fileNameView,
                                                                                                                               userId: metadata.userId,
                                                                                                                               urlBase: metadata.urlBase))

            await self.database.addMetadataAsync(metadata)
        }
    }

    func audioMeterDidUpdate(_ db: Float) {

        // print("db level: %f", db)

        self.recording.recorder?.updateMeters()
        let ALPHA = 0.05
        let peakPower = pow(10, (ALPHA * Double((self.recording.recorder?.peakPower(forChannel: 0))!)))
        var rate: Double = 0.0
        if peakPower <= 0.2 {
            rate = 0.2
        } else if peakPower > 0.9 {
            rate = 1.0
        } else {
            rate = peakPower
        }

        voiceRecordHUD.update(CGFloat(rate))
        voiceRecordHUD.fillColor = UIColor.green

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.second]
        formatter.unitsStyle = .full
        durationLabel.text = formatter.string(from: startDate, to: Date())
    }
}

@objc public protocol NCAudioRecorderDelegate: AVAudioRecorderDelegate {
    @objc optional func audioMeterDidUpdate(_ dB: Float)
}

open class NCAudioRecorder: NSObject {
    public enum State: Int {
        case none, record, play
    }

    static var directory: String {
        return NSTemporaryDirectory()
    }

    open weak var delegate: NCAudioRecorderDelegate?
    open fileprivate(set) var url: URL
    open fileprivate(set) var state: State = .none

    open var bitRate = 192000
    open var sampleRate = 44100.0
    open var channels = 1

    var recorder: AVAudioRecorder?
    fileprivate var player: AVAudioPlayer?
    fileprivate var link: CADisplayLink?

    var metering: Bool {
        return delegate?.responds(to: #selector(NCAudioRecorderDelegate.audioMeterDidUpdate(_:))) == true
    }

    // MARK: - Initializers

    public init(to fileName: String) {
        url = URL(fileURLWithPath: NCAudioRecorder.directory).appendingPathComponent(fileName)
        super.init()

        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord)
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(AVAudioSession.PortOverride.speaker)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print(error)
        }
    }

    deinit {
        print("deinit NCAudioRecorder")

        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print(error)
        }
    }

    // MARK: - Record

    open func prepare() throws {

        let settings: [String: AnyObject] = [
            AVFormatIDKey: NSNumber(value: Int32(kAudioFormatAppleLossless) as Int32),
            AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue as AnyObject,
            AVEncoderBitRateKey: bitRate as AnyObject,
            AVNumberOfChannelsKey: channels as AnyObject,
            AVSampleRateKey: sampleRate as AnyObject
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.prepareToRecord()
        recorder?.delegate = delegate
        recorder?.isMeteringEnabled = metering
    }

    open func record() throws {
        if recorder == nil {
            try prepare()
        }
        self.state = .record
        if self.metering {
            self.startMetering()
        }
        self.recorder?.record()
    }

    open func stop() {
        switch state {
        case .play:
            player?.stop()
            player = nil
        case .record:
            recorder?.stop()
            recorder = nil
            stopMetering()
        default:
            break
        }
        state = .none
    }

    // MARK: - Metering

    @objc func updateMeter() {
        guard let recorder = recorder else { return }
        recorder.updateMeters()
        let dB = recorder.averagePower(forChannel: 0)
        delegate?.audioMeterDidUpdate?(dB)
    }

    fileprivate func startMetering() {
        link = CADisplayLink(target: self, selector: #selector(NCAudioRecorder.updateMeter))
        link?.add(to: RunLoop.current, forMode: RunLoop.Mode.common)
    }

    fileprivate func stopMetering() {
        link?.invalidate()
        link = nil
    }
}

@IBDesignable
class VoiceRecordHUD: UIView {
    @IBInspectable var rate: CGFloat = 0.0
    @IBInspectable var fillColor: UIColor = UIColor.green {
        didSet {
            setNeedsDisplay()
        }
    }

    var image: UIImage! {
        didSet {
            setNeedsDisplay()
        }
    }

    // MARK: - View Life Cycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        image = UIImage(named: "microphone")
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        image = UIImage(named: "microphone")
    }

    func update(_ rate: CGFloat) {
        self.rate = rate
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()
        context?.translateBy(x: 0, y: bounds.size.height)
        context?.scaleBy(x: 1, y: -1)

        context?.draw(image.cgImage!, in: bounds)
        context?.clip(to: bounds, mask: image.cgImage!)

        context?.setFillColor(fillColor.cgColor.components!)
        context?.fill(CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height * rate))
    }

    override func prepareForInterfaceBuilder() {
        let bundle = Bundle(for: type(of: self))
        image = UIImage(named: "microphone", in: bundle, compatibleWith: self.traitCollection)
    }
}
