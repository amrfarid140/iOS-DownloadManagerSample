//
//  DownloadManager.swift
//  BGTest
//
//  Created by Amr Yousef on 02/06/2022.
//

import Foundation
import UIKit

enum DownloadState : Codable {
	case queueed
	case started
	case errored
	case finished
}

struct DownloadRequest : Codable{
	let url: URL
	let fileName: String
	let storageLocaion: URL
}

struct DownloadProgress : Codable {
	let downloadedBytes : Int64
	let totalBytes: Int64
}

struct DownloadRequestWrapper : Codable {
	let id: Int?
	let request: DownloadRequest
	let state: DownloadState
	var progress: DownloadProgress? = nil
}

protocol DownloadManagerDelegate{
	func onRequestFailed(request: DownloadRequest, error: Error)
	func onRequestStarted(request: DownloadRequest)
	func onRequestFinished(request: DownloadRequest)
	func onDownloadProgress(request: DownloadRequest, progress: DownloadProgress)
}

class DownloadManagerURLSessionDownloadDelegate: NSObject, URLSessionDownloadDelegate {
	
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		if let error = error {
			let itemIndex = DownloadManager.shared.queue.reader { array in
				array.firstIndex { $0.id == task.taskIdentifier }
			}!
			let item = DownloadManager.shared.queue[itemIndex]
			let newItem = DownloadRequestWrapper(id: item.id, request: item.request, state: .errored)
			DownloadManager.shared.queue.remove(at: itemIndex)
			DownloadManager.shared.queue.append(newItem)
			DownloadManager.shared.delegates.forEach { delegate in
				DispatchQueue.main.async {
					delegate.onRequestFailed(request: item.request, error: error)
				}
			}
		}
		refillTasks()
	}
	
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
		let itemIndex = DownloadManager.shared.queue.reader { array in
			array.firstIndex { $0.id == downloadTask.taskIdentifier }
		}!
		
		let item = DownloadManager.shared.queue[itemIndex]
		var newItem = DownloadRequestWrapper(id: item.id, request: item.request, state: .started)
		newItem.progress = DownloadProgress(downloadedBytes: totalBytesWritten, totalBytes: totalBytesExpectedToWrite)
		DownloadManager.shared.queue.writer { array in
			array.remove(at: itemIndex)
			array.insert(newItem, at: itemIndex)
		}
		if item.progress == nil {
			DownloadManager.shared.delegates.forEach { delegate in
				DispatchQueue.main.async {
					delegate.onRequestStarted(request: item.request)
				}
			}
		} else {
			DownloadManager.shared.delegates.forEach { delegate in
				DispatchQueue.main.async {
					delegate.onDownloadProgress(request: item.request, progress: item.progress!)
				}
			}
		}
		print("\(downloadTask.taskIdentifier) task: \(totalBytesWritten) out of \(totalBytesExpectedToWrite)")
	}
	
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		let itemIndex = DownloadManager.shared.queue.reader { array in
			array.firstIndex { $0.id == downloadTask.taskIdentifier }
		}!
		let item = DownloadManager.shared.queue[itemIndex]
		let newItem = DownloadRequestWrapper(id: item.id, request: item.request, state: .finished)
		try! FileManager.default.moveItem(at: location, to: item.request.storageLocaion)
		DownloadManager.shared.queue.remove(at: itemIndex)
		DownloadManager.shared.queue.append(newItem)
		print("Item downloaded and moved")
		DispatchQueue.main.async {
			DownloadManager.shared.delegates.forEach { $0.onRequestFinished(request: item.request) }
		}
		refillTasks()
	}
	
	private func refillTasks() {
		let urlSession = DownloadManager.shared.urlSession
		let startedCount = DownloadManager.shared.queue.reader { array in
			array.filter { $0.state == .started }
		}
		
		if startedCount.count == 0 {
			let toStart = DownloadManager.shared.queue.reader { array in
				array.filter({ wrapper in
					wrapper.state == .queueed
				}).prefix(DownloadManager.shared.downloadBatchSize)
			}
			toStart.forEach { wrapper in
				DownloadManager.shared.queue.writer { queueArray in
					let task = urlSession.downloadTask(with: wrapper.request.url)
					task.priority = URLSessionTask.highPriority
					queueArray.removeAll { item in
						item.request.fileName == wrapper.request.fileName
					}
					queueArray.append(DownloadRequestWrapper(id: task.taskIdentifier, request: wrapper.request, state: .started))
					task.resume()
				}
			}
		}
		
	}
	
	func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
		print("Batch done!")
		refillTasks()
		DispatchQueue.main.async {
			(UIApplication.shared.delegate as? AppDelegate)?.urlSessionDidFinishEvents(forBackgroundURLSession: session)
		}
	}
}

class DownloadManager : NSObject {
	static let shared: DownloadManager = DownloadManager()
	var downloadBatchSize = 20
	fileprivate var queue: SynchronizedArray<DownloadRequestWrapper> = SynchronizedArray("download_queue")
	fileprivate let urlSession: URLSession
	fileprivate let operationQueue = OperationQueue()
	fileprivate var delegates: [DownloadManagerDelegate] = []
	fileprivate let sessionDelegate = DownloadManagerURLSessionDownloadDelegate()
	
	override init() {
		let config = URLSessionConfiguration.background(withIdentifier: "download_queue")
		config.sessionSendsLaunchEvents = true
		config.isDiscretionary = false
		urlSession = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
		super.init()
		
		// Restart any item that hasn't been finished when the app went was closed
		//		queue.replace { item in
		//			if (item.state != .finished) {
		//				let task = self.urlSession.downloadTask(with: item.request.url)
		//				task.resume()
		//				return DownloadRequestWrapper(id: task.taskIdentifier, request: item.request, state: .queueed)
		//			} else {
		//				return item
		//			}
		//		}
		
	}
	
	func addDelegate(_ delegate: DownloadManagerDelegate) {
		delegates.append(delegate)
	}
	
	func enqueue(requests: [DownloadRequest]) {
		urlSession.getAllTasks { [self] tasks in
			if tasks.count == 0 {
				let chunks = requests.chunked(into: downloadBatchSize)
				chunks.first?.forEach({ request in
					queue.asyncWriter { array in
						let task = self.urlSession.downloadTask(with: request.url)
						task.priority = URLSessionTask.highPriority
						array.append(DownloadRequestWrapper(id: task.taskIdentifier, request: request, state: .started))
						task.resume()
					}
				})
				chunks.suffix(chunks.count - 1).forEach { chunk in
					queue.append(contentsOf: chunk.map({ request in
						DownloadRequestWrapper(id: nil, request: request, state: .queueed)
					}))
				}
			} else {
				queue.append(contentsOf: requests.map({ request in
					DownloadRequestWrapper(id: nil, request: request, state: .queueed)
				}))
			}
		}
	}
	
	func getAll() -> [DownloadRequestWrapper] {
		return queue.reader { array in array }
	}
}

extension Array {
	func chunked(into size: Int) -> [[Element]] {
		return stride(from: 0, to: count, by: size).map {
			Array(self[$0 ..< Swift.min($0 + size, count)])
		}
	}
}

