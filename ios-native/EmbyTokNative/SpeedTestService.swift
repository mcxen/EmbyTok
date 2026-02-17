import Foundation

final class SpeedTestService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func runTest(url: URL, bytes: Int = 2 * 1024 * 1024, completion: @escaping (Result<(Double, Double), Error>) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-\(bytes - 1)", forHTTPHeaderField: "Range")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let start = CFAbsoluteTimeGetCurrent()
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data, !data.isEmpty else {
                completion(.failure(NSError(domain: "SpeedTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "没有获取到测速数据"])))
                return
            }
            let duration = CFAbsoluteTimeGetCurrent() - start
            let bits = Double(data.count) * 8.0
            let mbps = bits / duration / 1_000_000.0
            completion(.success((mbps, duration)))
        }
        task.resume()
    }
}
