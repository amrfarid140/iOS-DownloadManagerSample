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

struct DownloadRequestWrapper : Codable {
	let id: Int?
	let request: DownloadRequest
	let state: DownloadState
}

protocol DownloadManagerDelegate{
	func onRequestFailed(request: DownloadRequest, error: Error)
	func onRequestStarted(request: DownloadRequest)
	func onRequestFinished(request: DownloadRequest)
}

class DownloadManagerURLSessionDownloadDelegate: NSObject, URLSessionDownloadDelegate {
	
	func urlSession(_ session: URLSession, task: URLSessionTask, willBeginDelayedRequest request: URLRequest, completionHandler: @escaping (URLSession.DelayedRequestDisposition, URLRequest?) -> Void) {
		let itemIndex = DownloadManager.shared.queue.reader { array in
			array.firstIndex { $0.id == task.taskIdentifier }
		}
		if let itemIndex = itemIndex {
			let item = DownloadManager.shared.queue[itemIndex]
			DownloadManager.shared.queue.writer { array in
				array.remove(at: itemIndex)
				array.insert(DownloadRequestWrapper(id: item.id, request: item.request, state: .started), at: itemIndex)
			}
			DownloadManager.shared.delegates.forEach { delegate in
				DispatchQueue.main.async {
					delegate.onRequestStarted(request: item.request)
				}
			}
		}
		completionHandler(.continueLoading, nil)
	}
	
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		if let error = error {
			let itemIndex = DownloadManager.shared.queue.reader { array in
				array.firstIndex { $0.id == task.taskIdentifier }
			}
			if let itemIndex = itemIndex {
				let item = DownloadManager.shared.queue[itemIndex]
				DownloadManager.shared.queue.remove(at: itemIndex)
				DownloadManager.shared.queue.writer { array in
					array.remove(at: itemIndex)
					array.insert(DownloadRequestWrapper(id: item.id, request: item.request, state: .errored), at: itemIndex)
				}
				DownloadManager.shared.delegates.forEach { delegate in
					DispatchQueue.main.async {
						delegate.onRequestFailed(request: item.request, error: error)
					}
				}
			}
		}
	}
	
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
		print("\(downloadTask.taskIdentifier) task: \(totalBytesWritten) out of \(totalBytesExpectedToWrite)")
	}
	
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		let itemIndex = DownloadManager.shared.queue.reader { array in
			array.firstIndex { $0.id == downloadTask.taskIdentifier }
		}
		if let itemIndex = itemIndex {
			let item = DownloadManager.shared.queue[itemIndex]
			try! FileManager.default.moveItem(at: location, to: item.request.storageLocaion)
			print("Item downloaded and moved")
			DispatchQueue.main.async {
				DownloadManager.shared.delegates.forEach { $0.onRequestFinished(request: item.request) }
			}
			DownloadManager.shared.queue.writer { array in
				array.remove(at: itemIndex)
				array.insert(DownloadRequestWrapper(id: item.id, request: item.request, state: .finished), at: itemIndex)
			}
		} else {
			print("Item not found")
		}
	}
	
	func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
		DispatchQueue.main.async {
			(UIApplication.shared.delegate as? AppDelegate)?.urlSessionDidFinishEvents(forBackgroundURLSession: session)
		}
	}
}

class DownloadManager : NSObject {
	static let shared: DownloadManager = DownloadManager()
	fileprivate var queue: SynchronizedArray<DownloadRequestWrapper> = SynchronizedArray("download_queue")
	fileprivate let urlSession: URLSession
	fileprivate let operationQueue = OperationQueue()
	fileprivate var delegates: [DownloadManagerDelegate] = []
	fileprivate let sessionDelegate = DownloadManagerURLSessionDownloadDelegate()
	
	override init() {
		let config = URLSessionConfiguration.background(withIdentifier: "download_queue")
		config.isDiscretionary = false
		urlSession = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: operationQueue)
		operationQueue.maxConcurrentOperationCount = 1
		super.init()
		if (queue.count != 0) {
			queue.replace { item in
				if (item.state != .finished) {
					let task = self.urlSession.downloadTask(with: item.request.url)
					task.resume()
					return DownloadRequestWrapper(id: task.taskIdentifier, request: item.request, state: .queueed)
				} else {
					return item
				}
			}
		}
	}
	
	func addDelegate(_ delegate: DownloadManagerDelegate) {
		delegates.append(delegate)
	}
	
	func enqueue(request: DownloadRequest) {
		queue.asyncWriter { [self] array in
			let task = self.urlSession.downloadTask(with: request.url)
			task.priority = URLSessionTask.highPriority
			array.append(DownloadRequestWrapper(id: task.taskIdentifier, request: request, state: .queueed))
			task.resume()
		}
	}
	
	func getQueue() -> [DownloadRequestWrapper] {
		return queue.array
	}
}

