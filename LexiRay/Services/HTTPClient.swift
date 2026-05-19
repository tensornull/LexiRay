import Foundation

struct HTTPLineStream {
  let lines: AsyncThrowingStream<String, Error>
  let response: URLResponse
}

@MainActor
protocol HTTPClient {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
  func lineStream(for request: URLRequest) async throws -> HTTPLineStream
}

extension URLSession: HTTPClient {
  func lineStream(for request: URLRequest) async throws -> HTTPLineStream {
    let (bytes, response) = try await bytes(for: request)
    let lines = AsyncThrowingStream<String, Error> { continuation in
      let task = Task {
        do {
          for try await line in bytes.lines {
            if Task.isCancelled {
              break
            }
            continuation.yield(line)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }

    return HTTPLineStream(lines: lines, response: response)
  }
}
