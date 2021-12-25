//
//  SDPResourceLoader.swift
//  SDPUtils
//
//  Created by 金申生 on 2021/12/24.
//

import Foundation
import AVFoundation
import FCFileManager
import CoreServices
import SDPUtils

@objcMembers
public class SDPResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    public var password: String = ""
        
    private var fileHandle: FileHandle?
    
    private var timer: DispatchSourceTimer?
        
    private var loadingRequest: AVAssetResourceLoadingRequest?
    
    private var offset: Int64 = 0
    
    private var fileSize: Int64 = 0
    
    public init(filePath: String) {
        super.init()
        self.fileHandle = FileHandle(forReadingAtPath: filePath)
        self.fileSize = FCFileManager.sizeOfFile(atPath: filePath).int64Value
    }
    
    deinit {
        self.finishLoadingRequest()
        self.fileHandle?.closeFile()
        self.fileHandle = nil
    }
    
    func mimeType(_ fileExtension: String) -> String? {
        guard let extUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileExtension as CFString, nil)?.takeUnretainedValue() else {
            return nil
        }
        
        guard let mimeUTI = UTTypeCopyPreferredTagWithClass(extUTI, kUTTagClassMIMEType)
        else {
            return nil
        }

        return mimeUTI.takeRetainedValue() as String
    }
    
    public func onLoadingRequest(_ loadingRequest: AVAssetResourceLoadingRequest) {
        guard let _ = self.fileHandle, self.fileSize > 0 else {
            return
        }

        //finish last request
        self.finishLoadingRequest()
        
        if let contentInformationRequest = loadingRequest.contentInformationRequest {
            contentInformationRequest.contentType = self.mimeType(loadingRequest.request.url!.pathExtension)
            contentInformationRequest.contentLength = self.fileSize
            contentInformationRequest.isByteRangeAccessSupported = true
            Swift.print("check video, content type", contentInformationRequest.contentType!)
        }
        
        guard let dataRequest = loadingRequest.dataRequest else {
            return
        }
        
        Swift.print("check video, new request", dataRequest.requestedOffset, dataRequest.requestedLength)
        
        self.loadingRequest = loadingRequest
        self.offset = dataRequest.requestedOffset
        
        self.timer = DispatchSource.makeTimerSource(queue: .global())
        self.timer?.schedule(deadline: .now(), repeating: 0.1)
        self.timer?.setEventHandler(handler: { [weak self] in
            self?.responseData()
        })
        self.timer?.resume()
    }
    
    func finishLoadingRequest() {
        self.loadingRequest?.finishLoading()
        self.loadingRequest = nil
        self.timer?.cancel()
        self.timer = nil
    }
    
    @objc func responseData() {
        guard let dataRequest = self.loadingRequest?.dataRequest, let fileHandle = self.fileHandle else {
            return
        }
        
        if #available(iOS 13.0, *) {
            try? fileHandle.seek(toOffset: UInt64(self.offset))
        } else {
            // Fallback on earlier versions
        }
        
        let data = fileHandle.readData(ofLength: min(Int(33554432), dataRequest.requestedLength))
        Swift.print("check video, respond offset", self.offset, " size", Int64(data.count))
        NSData.encode(data, withKey: self.password, offset: self.offset)
        dataRequest.respond(with: data)
        self.offset = self.offset + Int64(data.count)
        
        if self.offset >= (dataRequest.requestedOffset + Int64(dataRequest.requestedLength)) {
            self.finishLoadingRequest()
            Swift.print("check video, finishLoading")
        }
    }
    
    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        DispatchQueue.global().async {
            self.onLoadingRequest(loadingRequest)
        }
        return true
    }
}
