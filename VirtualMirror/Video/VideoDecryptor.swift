import Foundation
import CommonCrypto
import os

class VideoDecryptor {
    private let logger = Logger(subsystem: "cloud.souris.virtualmirror", category: "VideoDecryptor")
    private var aesKey: Data?
    private var aesIV: Data?
    private var cryptorRef: CCCryptorRef?

    func configure(key: Data, iv: Data) {
        self.aesKey = key
        self.aesIV = iv

        // Release any existing cryptor
        if let ref = cryptorRef {
            CCCryptorRelease(ref)
            cryptorRef = nil
        }

        // Create a persistent CCCryptorRef — AirPlay uses a continuous CTR counter
        // across the entire video stream, NOT per-frame.
        var cryptor: CCCryptorRef?
        let status = key.withUnsafeBytes { keyPtr in
            iv.withUnsafeBytes { ivPtr in
                CCCryptorCreateWithMode(
                    CCOperation(kCCEncrypt),
                    CCMode(kCCModeCTR),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    ivPtr.baseAddress,
                    keyPtr.baseAddress,
                    key.count,
                    nil, 0, 0,
                    CCModeOptions(kCCModeOptionCTR_BE),
                    &cryptor
                )
            }
        }

        if status == kCCSuccess, let ref = cryptor {
            self.cryptorRef = ref
            logger.info("Video decryptor configured with key (\(key.count) bytes), iv (\(iv.count) bytes)")
        } else {
            logger.error("Failed to create AES-CTR cryptor: \(status)")
        }
    }

    var isConfigured: Bool {
        return cryptorRef != nil
    }

    func decrypt(data: Data) -> Data {
        guard let ref = cryptorRef else {
            return data
        }

        var outBuffer = [UInt8](repeating: 0, count: data.count)
        var outMoved: size_t = 0

        _ = data.withUnsafeBytes { dataPtr in
            CCCryptorUpdate(
                ref,
                dataPtr.baseAddress,
                data.count,
                &outBuffer,
                outBuffer.count,
                &outMoved
            )
        }

        return Data(outBuffer.prefix(outMoved))
    }

    deinit {
        if let ref = cryptorRef {
            CCCryptorRelease(ref)
        }
    }
}
