//
//  BGTestApp.swift
//  BGTest
//
//  Created by Amr Yousef on 02/06/2022.
//

import SwiftUI

@main
struct BGTestApp: App {
	@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	let xyz = XYZ()
    var body: some Scene {
        WindowGroup {
            ContentView(xyz: xyz)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
	private var backgroundCompletionHandler: (() -> Void)? = nil
	
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
		dump(Array(UserDefaults.standard.dictionaryRepresentation().keys))
		return true
	}
	
	func application(_ application: UIApplication,
					 handleEventsForBackgroundURLSession identifier: String,
					 completionHandler: @escaping () -> Void) {
		backgroundCompletionHandler = completionHandler
	}
	
	func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
		Task { @MainActor in
			guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
				  let backgroundCompletionHandler = appDelegate.backgroundCompletionHandler else {
				return
			}
			
			backgroundCompletionHandler()
		}
	}
}
