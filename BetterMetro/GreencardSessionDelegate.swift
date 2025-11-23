//
//  GreencardSessionDelegate.swift
//  BetterMetro
//
//  Created by Ethan Hopkins on 18/11/2025.
//


import Foundation

class GreencardSessionDelegate: NSObject, URLSessionTaskDelegate {
    
    /// Automatically re-attaches Authorization headers after redirects.
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        
        var modifiedRequest = request
        
        // Grab the original Authorization header
        if let originalAuth = task.originalRequest?.value(forHTTPHeaderField: "Authorization") {
            modifiedRequest.setValue(originalAuth, forHTTPHeaderField: "Authorization")
        }
        
        // Also preserve User-Agent (iOS may strip this too)
        if let ua = task.originalRequest?.value(forHTTPHeaderField: "User-Agent") {
            modifiedRequest.setValue(ua, forHTTPHeaderField: "User-Agent")
        }

        completionHandler(modifiedRequest)
    }
}