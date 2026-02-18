import Foundation

final class SpeedTestService {
    struct LiveUpdate {
        let downloadMbps: Double
        let uploadMbps: Double
        let progress: Double
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func runLiveTest(
        url: URL,
        sampleCount: Int = 12,
        sampleBytes: Int = 768 * 1024,
        onUpdate: @escaping (LiveUpdate) -> Void,
        completion: @escaping (Result<LiveUpdate, Error>) -> Void
    ) {
        let safeSamples = max(1, sampleCount)
        let safeBytes = max(256 * 1024, sampleBytes)
        var downloadSamples: [Double] = []
        var uploadSamples: [Double] = []

        func runSample(at index: Int) {
            if index >= safeSamples {
                let finalDownload = Self.average(of: downloadSamples)
                let finalUpload = Self.average(of: uploadSamples)
                let result = LiveUpdate(downloadMbps: finalDownload, uploadMbps: finalUpload, progress: 1)
                DispatchQueue.main.async {
                    completion(.success(result))
                }
                return
            }

            let startedAt = CFAbsoluteTimeGetCurrent()
            self.measureDownload(url: url, bytes: safeBytes) { result in
                switch result {
                case .failure(let error):
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                case .success(let downloadMbps):
                    downloadSamples.append(downloadMbps)
                    let estimatedUpload = max(0.1, downloadMbps * 0.35)
                    uploadSamples.append(estimatedUpload)

                    let update = LiveUpdate(
                        downloadMbps: Self.average(of: downloadSamples),
                        uploadMbps: Self.average(of: uploadSamples),
                        progress: Double(index + 1) / Double(safeSamples)
                    )
                    DispatchQueue.main.async {
                        onUpdate(update)
                    }

                    let elapsed = CFAbsoluteTimeGetCurrent() - startedAt
                    let wait = max(0, 1.0 - elapsed)
                    DispatchQueue.global().asyncAfter(deadline: .now() + wait) {
                        runSample(at: index + 1)
                    }
                }
            }
        }

        runSample(at: 0)
    }

    private func measureDownload(url: URL, bytes: Int, completion: @escaping (Result<Double, Error>) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-\(bytes - 1)", forHTTPHeaderField: "Range")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12

        let start = CFAbsoluteTimeGetCurrent()
        session.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data, !data.isEmpty else {
                completion(.failure(NSError(domain: "SpeedTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "没有获取到测速数据"])))
                return
            }
            let duration = max(CFAbsoluteTimeGetCurrent() - start, 0.001)
            let bits = Double(data.count) * 8.0
            let mbps = bits / duration / 1_000_000.0
            completion(.success(mbps))
        }.resume()
    }

    private static func average(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
