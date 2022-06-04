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
	
	@Published var requests: [DownloadRequestWrapper] = []
	
	init() {
		requests = DownloadManager.shared.getAll()
	}
	
	func onRequestFailed(request: DownloadRequest, error: Error) {
		requests = requests.map { existingRequest in
			if existingRequest.request.fileName == request.fileName {
				return DownloadRequestWrapper(id: nil, request: existingRequest.request, state: .errored)
			} else {
				return existingRequest
			}
		}
	}
	
	func onRequestStarted(request: DownloadRequest) {
		requests = requests.map { existingRequest in
			if existingRequest.request.fileName == request.fileName {
				return DownloadRequestWrapper(id: nil, request: existingRequest.request, state: .started)
			} else {
				return existingRequest
			}
		}
	}
	
	func onRequestFinished(request: DownloadRequest) {
		requests = requests.map { existingRequest in
			if existingRequest.request.fileName == request.fileName {
				return DownloadRequestWrapper(id: nil, request: existingRequest.request, state: .finished)
			} else {
				return existingRequest
			}
		}
	}
	
	func getRequestState(name: String) -> DownloadState {
		if let request = requests.first(where: { request in request.request.fileName == name }) {
			return request.state
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
						let requests = response!.data.results.map { character in
							DownloadRequest(
								url: URL(string: "https://assets.pippa.io/shows/609e4b3069be6d6524986cee/1621410644716-c0101be2c3d5fd99355ce551a7e17497.mp3")!,
								fileName: character.name,
								storageLocaion: url.appendingPathComponent("\(character.name)")
							)
						}
						DownloadManager.shared.enqueue(requests: requests)
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
