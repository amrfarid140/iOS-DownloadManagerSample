//
//  ContentView.swift
//  BGTest
//
//  Created by Amr Yousef on 02/06/2022.
//
import Foundation
import SwiftUI

struct CharacterDataWrapper : Codable {
	let data : CharacterDataContainer
}

struct CharacterDataContainer : Codable {
	let results : [Character]
}

struct Character : Codable {
	let name: String
	let thumbnail : CharacterImage
}

struct CharacterImage : Codable {
	let path: String
}

class XYZ : DownloadManagerDelegate, ObservableObject {
	
	@Published var requests: [DownloadRequestWrapper] = []
	
	init() {
		requests = DownloadManager.shared.getAll()
	}
	
	func onRequestFailed(request: DownloadRequest, error: Error) {
		updateRequests(request, state: .errored)
	}
	
	func onRequestStarted(request: DownloadRequest) {
		updateRequests(request, state: .started)
	}
	
	func onRequestFinished(request: DownloadRequest) {
		updateRequests(request, state: .finished)
	}
	
	func onDownloadProgress(request: DownloadRequest, progress: DownloadProgress) {
		updateRequests(request, state: .started, progress: progress)
	}
	
	private func updateRequests(_ request: DownloadRequest, state: DownloadState, progress: DownloadProgress? = nil) {
		let itemIndex = requests.firstIndex(where: { $0.request.fileName == request.fileName })
		if let itemIndex = itemIndex {
			requests.remove(at: itemIndex)
		}
		var newRequest = DownloadRequestWrapper(id: nil, request: request, state: state)
		newRequest.progress = progress
		requests.append(newRequest)
	}
	
	func getRequestState(name: String) -> DownloadState {
		if let request = requests.first(where: { request in request.request.fileName == name }) {
			return request.state
		}
		return .queueed
	}
}

struct Item {
	let filename: String
	let url: URL
}

struct ContentView: View {
	@StateObject var xyz: XYZ = XYZ()
	@State var timeTaken: String = ""
	let items: [Item] = Edition.links.map { link in
		let url = URL(string: link)!
		return Item(filename: url.lastPathComponent, url: url)
	}
	var body: some View {
		let hasFinished = items.map { item in
			xyz.requests.first(where: { $0.request.fileName == item.filename })?.state == .finished
		}.reduce(true) { bool, item in
			bool && item
		}
		
		return ZStack {
			VStack(alignment: .leading) {
				if (hasFinished) {
					let startTimeDouble = UserDefaults.standard.double(forKey: "start_time")
					let endTimeDouble = UserDefaults.standard.double(forKey: "end_time")
					let startTime = Date(timeIntervalSince1970: startTimeDouble)
					let endTime = Date(timeIntervalSince1970: endTimeDouble)
					let (_ , _ , hour, minute, second) = endTime - startTime
					Text("Download Time: \(hour!) h: \(minute!) m: \(second!) s")
				}
				
				ScrollView {
					LazyVStack(alignment: .leading) {
						ForEach(items, id: \.filename) { item in
							HStack {
								Text(item.filename)
								Spacer()
								let request = xyz.requests.first(where: { $0.request.fileName == item.filename })
								let state = request?.state
								let progress = Double(request?.progress?.downloadedBytes ?? 0) / Double(request?.progress?.totalBytes ?? 1)
								switch state {
								case .finished:
									Text("Downloaded").foregroundColor(Color.green)
								case .started:
									Text(String(format: "Downloading (%.2f%%)", progress * 100)).foregroundColor(Color.primary)
								case .errored:
									Text("Failed").foregroundColor(Color.red)
								default:
									Text("Waiting...")
								}
							}.padding()
						}
					}
				}
				Button("Start Download") {
					let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let requests = items.map { item in
						DownloadRequest(
							url: item.url,
							fileName: item.filename,
							storageLocaion: url.appendingPathComponent(item.filename)
						)
					}
					DownloadManager.shared.enqueue(requests: requests)
					UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "start_time")
				}.buttonStyle(.borderedProminent)
			}
		}
		.onAppear {
			DownloadManager.shared.addDelegate(xyz)
		}
		.scenePadding()
	}
}

extension Date {

	static func -(recent: Date, previous: Date) -> (month: Int?, day: Int?, hour: Int?, minute: Int?, second: Int?) {
		let day = Calendar.current.dateComponents([.day], from: previous, to: recent).day
		let month = Calendar.current.dateComponents([.month], from: previous, to: recent).month
		let hour = Calendar.current.dateComponents([.hour], from: previous, to: recent).hour
		let minute = Calendar.current.dateComponents([.minute], from: previous, to: recent).minute
		let second = Calendar.current.dateComponents([.second], from: previous, to: recent).second

		return (month: month, day: day, hour: hour, minute: minute, second: second)
	}

}
