//
//  NCNetworking.swift
//  Nextcloud
//
//  Created by Marino Faggiana on 23/10/19.
//  Copyright © 2019 Marino Faggiana. All rights reserved.
//
//  Author Marino Faggiana <marino.faggiana@nextcloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import UIKit
import OpenSSL
import NextcloudKit
import Alamofire
import Queuer
import SwiftUI

@objc protocol ClientCertificateDelegate {
    func onIncorrectPassword()
    func didAskForClientCertificate()
}

protocol NCTransferDelegate: AnyObject {
    var sceneIdentifier: String { get }
    func transferProgressDidUpdate(progress: Float,
                                   totalBytes: Int64,
                                   totalBytesExpected: Int64,
                                   fileName: String,
                                   serverUrl: String)

    func transferChange(status: String, metadata: tableMetadata, error: NKError)
    func transferChange(status: String, metadatasError: [tableMetadata: NKError])
    func transferReloadData(serverUrl: String?, status: Int?)
    func transferRequestData(serverUrl: String?)
    func transferCopy(metadata: tableMetadata, error: NKError)
    func transferMove(metadata: tableMetadata, error: NKError)
    func transferFileExists(ocId: String, exists: Bool)
}

extension NCTransferDelegate {
    func transferProgressDidUpdate(progress: Float,
                                   totalBytes: Int64,
                                   totalBytesExpected: Int64,
                                   fileName: String,
                                   serverUrl: String) {}
    func transferChange(status: String, metadata: tableMetadata, error: NKError) {}
    func transferChange(status: String, metadatasError: [tableMetadata: NKError]) {}
    func transferReloadData(serverUrl: String?, status: Int?) {}
    func transferRequestData(serverUrl: String?) {}
    func transferCopy(metadata: tableMetadata, error: NKError) {}
    func transferMove(metadata: tableMetadata, error: NKError) {}
    func transferFileExists(ocId: String, exists: Bool) {}
}

class NCNetworking: @unchecked Sendable, NextcloudKitDelegate {
    static let shared = NCNetworking()

    struct FileNameServerUrl: Hashable {
        var fileName: String
        var serverUrl: String
    }

    let sessionDownload = NextcloudKit.shared.nkCommonInstance.identifierSessionDownload
    let sessionDownloadBackground = NextcloudKit.shared.nkCommonInstance.identifierSessionDownloadBackground
    let sessionDownloadBackgroundExt = NextcloudKit.shared.nkCommonInstance.identifierSessionDownloadBackgroundExt

    let sessionUpload = NextcloudKit.shared.nkCommonInstance.identifierSessionUpload
    let sessionUploadBackground = NextcloudKit.shared.nkCommonInstance.identifierSessionUploadBackground
    let sessionUploadBackgroundWWan = NextcloudKit.shared.nkCommonInstance.identifierSessionUploadBackgroundWWan
    let sessionUploadBackgroundExt = NextcloudKit.shared.nkCommonInstance.identifierSessionUploadBackgroundExt

    let utilityFileSystem = NCUtilityFileSystem()
    let utility = NCUtility()
    let database = NCManageDatabase.shared
    let global = NCGlobal.shared
    let backgroundSession = NKBackground(nkCommonInstance: NextcloudKit.shared.nkCommonInstance)

    var requestsUnifiedSearch: [DataRequest] = []
    var lastReachability: Bool = true
    var networkReachability: NKTypeReachability?
    weak var certificateDelegate: ClientCertificateDelegate?
    var p12Data: Data?
    var p12Password: String?
    var tapHudStopDelete = false

    var isOffline: Bool {
        return networkReachability == NKTypeReachability.notReachable || networkReachability == NKTypeReachability.unknown
    }
    var isOnline: Bool {
        return networkReachability == NKTypeReachability.reachableEthernetOrWiFi || networkReachability == NKTypeReachability.reachableCellular
    }

    // Capabilities
    var capabilities = ThreadSafeDictionary<String, NKCapabilities.Capabilities>()

    // Delegate for multi scene
    private var transferDelegates = NSHashTable<AnyObject>.weakObjects()

    func addDelegate(_ delegate: NCTransferDelegate) {
        transferDelegates.add(delegate)
    }

    func removeDelegate(_ delegate: NCTransferDelegate) {
        transferDelegates.remove(delegate)
    }

    func notifyAllDelegates(_ block: (NCTransferDelegate) -> Void) {
        for delegate in transferDelegates.allObjects {
            if let delegate = delegate as? NCTransferDelegate {
                block(delegate)
            }
        }
    }

    func notifyDelegate(forScene sceneIdentifier: String, _ block: (NCTransferDelegate) -> Void) {
        for delegate in transferDelegates.allObjects {
            if let delegate = delegate as? NCTransferDelegate, delegate.sceneIdentifier == sceneIdentifier {
                block(delegate)
            }
        }
    }

    func notifyDelegates(forScene sceneIdentifier: String,
                         matching: (NCTransferDelegate) -> Void,
                         others: (NCTransferDelegate) -> Void) {
        for delegate in transferDelegates.allObjects {
            guard let delegate = delegate as? NCTransferDelegate
            else {
                continue
            }
            if delegate.sceneIdentifier == sceneIdentifier {
                matching(delegate)
            } else {
                others(delegate)
            }
        }
    }

    // OPERATIONQUEUE
    let downloadThumbnailQueue = Queuer(name: "downloadThumbnailQueue", maxConcurrentOperationCount: 10, qualityOfService: .default)
    let downloadThumbnailActivityQueue = Queuer(name: "downloadThumbnailActivityQueue", maxConcurrentOperationCount: 10, qualityOfService: .default)
    let downloadThumbnailTrashQueue = Queuer(name: "downloadThumbnailTrashQueue", maxConcurrentOperationCount: 10, qualityOfService: .default)
    let unifiedSearchQueue = Queuer(name: "unifiedSearchQueue", maxConcurrentOperationCount: 1, qualityOfService: .default)
    let saveLivePhotoQueue = Queuer(name: "saveLivePhotoQueue", maxConcurrentOperationCount: 1, qualityOfService: .default)
    let downloadAvatarQueue = Queuer(name: "downloadAvatarQueue", maxConcurrentOperationCount: 10, qualityOfService: .default)
    let fileExistsQueue = Queuer(name: "fileExistsQueue", maxConcurrentOperationCount: 10, qualityOfService: .default)

    // MARK: - init

    init() {
        if let account = database.getActiveTableAccount()?.account {
            getActiveAccountCertificate(account: account)
        }

        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: global.notificationCenterChangeUser), object: nil, queue: .main) { notification in
            if let userInfo = notification.userInfo {
                if let account = userInfo["account"] as? String {
                    self.getActiveAccountCertificate(account: account)
                }
            }
        }
    }

    // MARK: - Communication Delegate

    func networkReachabilityObserver(_ typeReachability: NKTypeReachability) {
        if typeReachability == NKTypeReachability.reachableCellular || typeReachability == NKTypeReachability.reachableEthernetOrWiFi {
            lastReachability = true
        } else {
            if lastReachability {
                let error = NKError(errorCode: global.errorNetworkNotAvailable, errorDescription: "")
                NCContentPresenter().messageNotification("_network_not_available_", error: error, delay: global.dismissAfterSecond, type: NCContentPresenter.messageType.info)
            }
            lastReachability = false
        }
        networkReachability = typeReachability
    }

    func authenticationChallenge(_ session: URLSession,
                                 didReceive challenge: URLAuthenticationChallenge,
                                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
            if let p12Data = self.p12Data,
               let cert = (p12Data, self.p12Password) as? UserCertificate,
               let pkcs12 = try? PKCS12(pkcs12Data: cert.data, password: cert.password, onIncorrectPassword: {
                   self.certificateDelegate?.onIncorrectPassword()
               }) {
                let creds = PKCS12.urlCredential(for: pkcs12)
                completionHandler(URLSession.AuthChallengeDisposition.useCredential, creds)
            } else {
                self.certificateDelegate?.didAskForClientCertificate()
                completionHandler(URLSession.AuthChallengeDisposition.cancelAuthenticationChallenge, nil)
            }
        } else {
            self.checkTrustedChallenge(session, didReceive: challenge, completionHandler: completionHandler)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
#if !EXTENSION
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate, let completionHandler = appDelegate.backgroundSessionCompletionHandler {
            nkLog(debug: "Called urlSessionDidFinishEvents for Background URLSession")
            appDelegate.backgroundSessionCompletionHandler = nil
            completionHandler()
        }
#endif
    }

    func request<Value>(_ request: DataRequest, didParseResponse response: AFDataResponse<Value>) { }

    // MARK: - Pinning check

    public func checkTrustedChallenge(_ session: URLSession,
                                      didReceive challenge: URLAuthenticationChallenge,
                                      completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let protectionSpace = challenge.protectionSpace
        let directoryCertificate = utilityFileSystem.directoryCertificates
        let host = protectionSpace.host
        let certificateSavedPath = (directoryCertificate as NSString).appendingPathComponent("\(host).der")

        guard let trust = protectionSpace.serverTrust,
              let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = certificates.first else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Salvataggio asincrono → nessun rischio per il main thread
        DispatchQueue.global(qos: .utility).async {
            self.saveX509Certificate(certificate, host: host, directoryCertificate: directoryCertificate)

            let isServerTrusted = SecTrustEvaluateWithError(trust, nil)
            let certificateCopyData = SecCertificateCopyData(certificate)
            let data = CFDataGetBytePtr(certificateCopyData)
            let size = CFDataGetLength(certificateCopyData)
            let certificateData = Data(bytes: data!, count: size)

            let tmpPath = (directoryCertificate as NSString).appendingPathComponent("\(host).tmp")
            try? certificateData.write(to: URL(fileURLWithPath: tmpPath), options: .atomic)

            var isTrusted = false

            if isServerTrusted {
                isTrusted = true
            } else if let savedData = try? Data(contentsOf: URL(fileURLWithPath: certificateSavedPath)),
                      savedData == certificateData {
                isTrusted = true
            }

            DispatchQueue.main.async {
                if isTrusted {
                    completionHandler(.useCredential, URLCredential(trust: trust))
                } else {
    #if !EXTENSION
                    (UIApplication.shared.delegate as? AppDelegate)?.trustCertificateError(host: host)
    #endif
                    completionHandler(.performDefaultHandling, nil)
                }
            }
        }
    }

    func writeCertificate(host: String) {
        let directoryCertificate = utilityFileSystem.directoryCertificates
        let certificateAtPath = directoryCertificate + "/" + host + ".tmp"
        let certificateToPath = directoryCertificate + "/" + host + ".der"

        if !utilityFileSystem.copyFile(atPath: certificateAtPath, toPath: certificateToPath) {
            nkLog(error: "Write certificare error")
        }
    }

    func saveX509Certificate(_ certificate: SecCertificate, host: String, directoryCertificate: String) {
        let certNamePathTXT = directoryCertificate + "/" + host + ".txt"
        let data: CFData = SecCertificateCopyData(certificate)
        let mem = BIO_new_mem_buf(CFDataGetBytePtr(data), Int32(CFDataGetLength(data)))
        let x509cert = d2i_X509_bio(mem, nil)

        if x509cert == nil {
            nkLog(error: "OpenSSL couldn't parse X509 Certificate")
        } else {
            // save details
            if FileManager.default.fileExists(atPath: certNamePathTXT) {
                do {
                    try FileManager.default.removeItem(atPath: certNamePathTXT)
                } catch { }
            }
            let fileCertInfo = fopen(certNamePathTXT, "w")
            if fileCertInfo != nil {
                let output = BIO_new_fp(fileCertInfo, BIO_NOCLOSE)
                X509_print_ex(output, x509cert, UInt(XN_FLAG_COMPAT), UInt(X509_FLAG_COMPAT))
                BIO_free(output)
            }
            fclose(fileCertInfo)
            X509_free(x509cert)
        }

        BIO_free(mem)
    }

    func checkPushNotificationServerProxyCertificateUntrusted(viewController: UIViewController?,
                                                              completion: @escaping (_ error: NKError) -> Void) {
        guard let host = URL(string: NCBrandOptions.shared.pushNotificationServerProxy)?.host else {
            return
        }

        NextcloudKit.shared.checkServer(serverUrl: NCBrandOptions.shared.pushNotificationServerProxy) { _, error in
            guard error == .success else {
                completion(.success)
                return
            }

            if error == .success {
                self.writeCertificate(host: host)
                completion(error)
            } else if error.errorCode == NSURLErrorServerCertificateUntrusted {
                let alertController = UIAlertController(title: NSLocalizedString("_ssl_certificate_untrusted_", comment: ""), message: NSLocalizedString("_connect_server_anyway_", comment: ""), preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: NSLocalizedString("_yes_", comment: ""), style: .default, handler: { _ in
                    self.writeCertificate(host: host)
                    completion(.success)
                }))
                alertController.addAction(UIAlertAction(title: NSLocalizedString("_no_", comment: ""), style: .default, handler: { _ in
                    completion(error)
                }))
                alertController.addAction(UIAlertAction(title: NSLocalizedString("_certificate_details_", comment: ""), style: .default, handler: { _ in
                    if let navigationController = UIStoryboard(name: "NCViewCertificateDetails", bundle: nil).instantiateInitialViewController() as? UINavigationController,
                       let vcCertificateDetails = navigationController.topViewController as? NCViewCertificateDetails {
                        vcCertificateDetails.host = host
                        viewController?.present(navigationController, animated: true)
                    }
                }))
                viewController?.present(alertController, animated: true)
            }
        }
    }

    private func getActiveAccountCertificate(account: String) {
        (self.p12Data, self.p12Password) = NCKeychain().getClientCertificate(account: account)
    }
}
