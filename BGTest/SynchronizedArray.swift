//
//  SynchronizedArray.swift
//  BGTest
//
//  Created by Amr Yousef on 02/06/2022.
//

import Foundation

class SynchronizedArray<T : Codable> {
	var array: [T]
	private var key: String
	private let accessQueue = DispatchQueue(label: "com.domain.app.reader-writer", attributes: .concurrent)

	init(_ key: String) {
		self.key = key
		if let jsonString = UserDefaults.standard.string(forKey: key),
			let data = jsonString.data(using: .utf8),
		   let array = try? JSONDecoder().decode([T].self, from: data) {
			self.array = array
		} else {
			self.array = []
		}
	}

	subscript(index: Int) -> T {
		get { reader { $0[index] } }
		set { writer { $0[index] = newValue } }
	}

	var count: Int {
		reader { $0.count }
	}

	func append(_ newElement: T) {
		writer { $0.append(newElement) }
	}
	
	func append(contentsOf: [T]) {
		writer { $0.append(contentsOf: contentsOf) }
	}

	func remove(at index: Int) {
		writer { $0.remove(at: index) }
	}

	func reader<U>(_ block: ([T]) throws -> U) rethrows -> U {
		try accessQueue.sync { try block(array) }
	}
	
	func replace(_ transform: @escaping (T) throws -> T) {
		accessQueue.sync {
			self.array = try! self.array.map(transform)
		}
	}
	
	func map<U>(_ transform: @escaping (T) throws -> U) -> [U] {
		return accessQueue.sync {
			try! self.array.map(transform)
		}
	}

	func asyncWriter(_ block: @escaping (inout [T]) -> Void) {
		accessQueue.async(flags: .barrier) {
			block(&self.array)
			if let data = try? JSONEncoder().encode(self.array),
			   let jsonString = String(data: data, encoding: .utf8) {
				UserDefaults.standard.set(jsonString, forKey: self.key)
			}
		}
	}
	
	func writer(_ block: @escaping (inout [T]) -> Void) {
		accessQueue.sync {
			block(&self.array)
			if let data = try? JSONEncoder().encode(self.array),
			   let jsonString = String(data: data, encoding: .utf8) {
				UserDefaults.standard.set(jsonString, forKey: self.key)
			}
		}
	}
}
