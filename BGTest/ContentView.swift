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

struct ContentView: View {
	@StateObject var xyz: XYZ = XYZ()
	
	var body: some View {
		ZStack {
			VStack {
				ScrollView {
					LazyVStack(alignment: .leading) {
						ForEach(Edition.links, id: \.self) { item in
							HStack {
								Text(item)
								Spacer()
								let request = xyz.requests.first(where: { $0.request.fileName == item })
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
                    let requests = Edition.links.map { item in
						DownloadRequest(
							url: URL(string: item)!,
							fileName: item,
							storageLocaion: url.appendingPathComponent("\(item)")
						)
					}
					DownloadManager.shared.enqueue(requests: requests)
				}.buttonStyle(.borderedProminent)
			}
		}
		.onAppear {
			DownloadManager.shared.addDelegate(xyz)
		}
		.scenePadding()
	}
}
