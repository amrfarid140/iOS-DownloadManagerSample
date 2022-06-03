//
//  ContentView.swift
//  BGTest
//
//  Created by Amr Yousef on 02/06/2022.
//
import Foundation
import SwiftUI
import CryptoKit

func MD5(string: String) -> String {
	let digest = Insecure.MD5.hash(data: string.data(using: .utf8) ?? Data())
	
	return digest.map {
		String(format: "%02hhx", $0)
	}.joined()
}

let publicKey = "f8370e1f339c2171cc909402d300ea44"
let privateKey = "f3ec46ac173c8f94d67c261e58f53f90b9b750bc"
let timestamp = Date().timeIntervalSince1970
let hash = MD5(string: "\(timestamp)\(privateKey)\(publicKey)")

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
	
	@Published var startedRequests: [DownloadRequest] = []
	@Published var failedRequests: [DownloadRequest] = []
	@Published var finishedRequests: [DownloadRequest] = []
	
	init() {
		let queue = DownloadManager.shared.getQueue()
		startedRequests = queue.filter({ it in
			it.state == .started
		}).map({ it in
			it.request
		})
		failedRequests = queue.filter({ it in
			it.state == .errored
		}).map({ it in
			it.request
		})
		finishedRequests = queue.filter({ it in
			it.state == .finished
		}).map({ it in
			it.request
		})
	}
	
	func onRequestFailed(request: DownloadRequest, error: Error) {
		failedRequests.append(request)
	}
	
	func onRequestStarted(request: DownloadRequest) {
		startedRequests.append(request)
	}
	
	func onRequestFinished(request: DownloadRequest) {
		finishedRequests.append(request)
	}
	
	func getRequestState(name: String) -> DownloadState {
		if startedRequests.firstIndex(where: { request in request.fileName == name }) != nil {
			return .started
		}
		if failedRequests.firstIndex(where: { request in request.fileName == name }) != nil {
			return .errored
		}
		if finishedRequests.firstIndex(where: { request in request.fileName == name }) != nil {
			return .finished
		}
		return .queueed
	}
}

struct ContentView: View {
	@State var response: CharacterDataWrapper? = nil
	@State var isError: Bool = false
	@ObservedObject var xyz: XYZ
	init(xyz: XYZ) {
		self.xyz = xyz
	}
	var body: some View {
		ZStack {
			if isError {
				Text("error")
			}
			if response == nil {
				Text("loading")
			}
			
			if response != nil {
				VStack {
					ScrollView {
						LazyVStack(alignment: .leading) {
							ForEach(response!.data.results, id: \.name) { character in
								HStack {
									Text(character.name)
									Spacer()
									switch xyz.getRequestState(name: character.name) {
									case.queueed:
										Text("queueed")
									case .finished:
										Text("finished")
									case .started:
										Text("started")
									case .errored:
										Text("errored")
										
									}
								}.padding()
							}
						}
					}
					Button("Start Download") {
						let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
						response!.data.results.forEach { character in
							DownloadManager.shared.enqueue(
								request: DownloadRequest(
									url: URL(string: "https://assets.pippa.io/shows/609e4b3069be6d6524986cee/1621410644716-c0101be2c3d5fd99355ce551a7e17497.mp3")!,
									fileName: character.name,
									storageLocaion: url.appendingPathComponent("\(character.name)")
								)
							)
						}
					}.buttonStyle(.borderedProminent)
				}
			}
		}
		.scenePadding()
		.task {
			let (data, _) = try! await URLSession.shared.data(from: URL(string: "https://gateway.marvel.com/v1/public/characters?ts=\(timestamp)&hash=\(hash)&apikey=\(publicKey)&limit=100")!)
			
			let decoder = JSONDecoder()
			response = try? decoder.decode(CharacterDataWrapper.self, from: data)
		}
	}
}
