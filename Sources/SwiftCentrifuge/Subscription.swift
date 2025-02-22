//
//  Subscription.swift
//  SwiftCentrifuge
//
//  Created by Alexander Emelin on 03/01/2019.
//  Copyright © 2019 Alexander Emelin. All rights reserved.
//

import Foundation

public enum CentrifugeSubscriptionStatus {
    case unsubscribed
    case subscribing
    case subscribeSuccess
    case subscribeError
}

public class CentrifugeSubscription {
    
    public let channel: String
    
    private var status: CentrifugeSubscriptionStatus = .unsubscribed
    private var isResubscribe = false
    private var needResubscribe = true

    private var lastOffset: UInt64 = 0
    private var recoverable: Bool = false
    private var needRecover: Bool = false
    private var lastEpoch: String = ""

    public weak var delegate: CentrifugeSubscriptionDelegate?
    
    private var callbacks: [String: ((Error?) -> ())] = [:]
    private weak var centrifuge: CentrifugeClient?
    
    init(centrifuge: CentrifugeClient, channel: String, delegate: CentrifugeSubscriptionDelegate) {
        self.centrifuge = centrifuge
        self.channel = channel
        self.delegate = delegate
        self.isResubscribe = false
    }
    
    public func subscribe() {
        self.centrifuge?.syncQueue.async { [weak self] in
            guard
                let strongSelf = self,
                strongSelf.status == .unsubscribed
                else { return }
            strongSelf.status = .subscribing
            strongSelf.needResubscribe = true
            if strongSelf.centrifuge?.status == .connected {
                strongSelf.resubscribe()
            }
        }
    }
    
    public func publish(data: Data, completion: @escaping (CentrifugePublishResult?, Error?) -> ()) {
        self.waitForSubscribe(completion: { [weak self, channel = self.channel] error in
            if let err = error {
                completion(nil, err)
            } else {
                self?.centrifuge?.publish(channel: channel, data: data, completion: completion)
            }
        })
    }
    
    public func presence(completion: @escaping (CentrifugePresenceResult?, Error?) -> ()) {
        self.waitForSubscribe(completion: { [weak self, channel = self.channel] error in
            if let err = error {
                completion(nil, err)
            } else {
                self?.centrifuge?.presence(channel: channel, completion: completion)
            }
        })
    }
    
    public func presenceStats(completion: @escaping (CentrifugePresenceStatsResult?, Error?) -> ()) {
        self.waitForSubscribe(completion: { [weak self, channel = self.channel] error in
            if let err = error {
                completion(nil, err)
            } else {
                self?.centrifuge?.presenceStats(channel: channel, completion: completion)
            }
        })
    }
    
    public func history(limit: Int32 = 0, since: CentrifugeStreamPosition? = nil, reverse: Bool = false, completion: @escaping (CentrifugeHistoryResult?, Error?) -> ()) {
        self.waitForSubscribe(completion: { [weak self, channel = self.channel] error in
            if let err = error {
                completion(nil, err)
            } else {
                self?.centrifuge?.history(channel: channel, limit: limit, since: since, reverse: reverse, completion: completion)
            }
        })
    }
    
    func sendSubscribe(channel: String, token: String) {
        let isRecover = self.needRecover && self.recoverable
        var streamPosition = StreamPosition()
        if isRecover {
            if self.lastOffset > 0 {
                streamPosition.offset = self.lastOffset
            }

            streamPosition.epoch = self.lastEpoch
        }
        self.centrifuge?.subscribe(channel: self.channel, token: token, isRecover: isRecover, streamPosition: streamPosition, completion: { [weak self, weak centrifuge = self.centrifuge] res, error in
            guard let centrifuge = centrifuge else { return }
            if let err = error {
                switch err {
                case CentrifugeError.replyError(let code, let message):
                    if code == 100 { // Internal error results into reconnect.
                        centrifuge.syncQueue.async { [weak centrifuge = centrifuge] in
                            centrifuge?.close(reason: "internal error", reconnect: true)
                        }
                        return
                    }
                    self?.centrifuge?.syncQueue.async { [weak self] in
                        guard let strongSelf = self else { return }
                        strongSelf.status = .subscribeError
                        strongSelf.centrifuge?.delegateQueue.addOperation { [weak self] in
                            guard let strongSelf = self else { return }
                            strongSelf.delegate?.onSubscribeError(strongSelf, CentrifugeSubscribeErrorEvent(code: code, message: message))
                        }
                        
                        for cb in strongSelf.callbacks.values {
                            cb(CentrifugeError.replyError(code: code, message: message))
                        }
                        
                        strongSelf.callbacks.removeAll(keepingCapacity: true)
                    }
                case CentrifugeError.timeout:
                    centrifuge.syncQueue.async { [weak centrifuge = centrifuge] in
                        centrifuge?.close(reason: "timeout", reconnect: true)
                    }
                    return
                default:
                    centrifuge.syncQueue.async { [weak centrifuge = centrifuge] in
                        centrifuge?.close(reason: "subscription error", reconnect: true)
                    }
                    return
                }
            }
            guard let result = res else { return }
            self?.centrifuge?.syncQueue.async { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.isResubscribe = true
                strongSelf.recoverable = result.recoverable
                strongSelf.lastEpoch = result.epoch
                for cb in strongSelf.callbacks.values {
                    cb(nil)
                }
                strongSelf.callbacks.removeAll(keepingCapacity: true)
                strongSelf.status = .subscribeSuccess
                strongSelf.centrifuge?.delegateQueue.addOperation { [weak self] in
                    guard let strongSelf = self else { return }
                    result.publications.forEach { [weak self] pub in
                        guard let strongSelf = self else { return }
                        var info: CentrifugeClientInfo? = nil;
                        if pub.hasInfo {
                            info = CentrifugeClientInfo(client: pub.info.client, user: pub.info.user, connInfo: pub.info.connInfo, chanInfo: pub.info.chanInfo)
                        }
                        let event = CentrifugePublishEvent(data: pub.data, offset: pub.offset, info: info)
                        strongSelf.delegate?.onPublish(strongSelf, event)
                        strongSelf.setLastOffset(pub.offset)
                    }
                    if result.publications.isEmpty {
                        strongSelf.setLastOffset(result.offset)
                    }
                    strongSelf.delegate?.onSubscribeSuccess(
                        strongSelf,
                        CentrifugeSubscribeSuccessEvent(resubscribe: strongSelf.isResubscribe, recovered: result.recovered)
                    )
                }
            }
        })
    }
    
    func resubscribeIfNecessary() {
        self.centrifuge?.syncQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            if (strongSelf.status == .unsubscribed || strongSelf.status == .subscribing) && strongSelf.needResubscribe {
                strongSelf.status = .subscribing
                strongSelf.resubscribe()
            }
        }
    }
    
    func resubscribe() {
        guard let centrifuge = self.centrifuge else { return }
        if self.channel.hasPrefix(centrifuge.config.privateChannelPrefix) {
            centrifuge.getSubscriptionToken(channel: self.channel, completion: { [weak self] token in
                guard let strongSelf = self else { return }
                strongSelf.centrifuge?.syncQueue.async { [weak self] in
                    guard let strongSelf = self, strongSelf.status == .subscribing else { return }
                    strongSelf.sendSubscribe(channel: strongSelf.channel, token: token)
                    strongSelf.needRecover = true
                }
            })
        } else {
            self.centrifuge?.syncQueue.async { [weak self] in
                guard let strongSelf = self, strongSelf.status == .subscribing else { return }
                strongSelf.sendSubscribe(channel: strongSelf.channel, token: "")
                strongSelf.needRecover = true
            }
        }
    }
    
    private func waitForSubscribe(completion: @escaping (Error?) -> ()) {
        self.centrifuge?.syncQueue.async { [weak self] in
            guard let strongSelf = self, let timeout = strongSelf.centrifuge?.config.timeout else { return }
            
            if !strongSelf.needResubscribe {
                completion(CentrifugeError.unsubscribed)
                return
            }
            
            let needWait = strongSelf.status == .subscribing || (strongSelf.status == .unsubscribed && strongSelf.needResubscribe)
            if !needWait {
                completion(nil)
                return
            }
            
            let uid = UUID().uuidString
            
            let timeoutTask = DispatchWorkItem { [weak self] in
                self?.callbacks[uid] = nil
                completion(CentrifugeError.timeout)
            }
            
            strongSelf.callbacks[uid] = { error in
                timeoutTask.cancel()
                completion(error)
            }
            
            strongSelf.centrifuge?.syncQueue.asyncAfter(deadline: .now() + timeout, execute: timeoutTask)
        }
    }

    // Access must be serialized from outside.
    func moveToUnsubscribed() {
        if self.status != .subscribeSuccess && self.status != .subscribeError {
            return
        }
        let previousStatus = self.status
        self.status = .unsubscribed
        if previousStatus != .subscribeSuccess {
            return
        }
        // Only call unsubscribe event if Subscription was successfully subscribed.
        self.centrifuge?.delegateQueue.addOperation { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.delegate?.onUnsubscribe(
                strongSelf,
                CentrifugeUnsubscribeEvent()
            )
        }
    }
    
    func setNeedRecover(_ needRecover: Bool) {
        self.centrifuge?.syncQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.needRecover = needRecover
        }
    }

    func setLastOffset(_ lastOffset: UInt64) {
        self.centrifuge?.syncQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.lastOffset = lastOffset
        }
    }

    public func unsubscribe() {
        self.centrifuge?.syncQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.needResubscribe = false
            strongSelf.needRecover = false
            strongSelf.moveToUnsubscribed()
            strongSelf.centrifuge?.unsubscribe(sub: strongSelf)
        }
    }

    // onRemove should only be called from Client.removeSubscription.
    func onRemove() {
        self.centrifuge?.syncQueue.async {
            if self.status != .subscribeSuccess && self.status != .subscribeError {
                return
            }
            let previousStatus = self.status
            self.status = .unsubscribed
            if previousStatus != .subscribeSuccess {
                return
            }
            // Only call unsubscribe event if Subscription was successfully subscribed.
            self.centrifuge?.delegateQueue.addOperation {
                self.delegate?.onUnsubscribe(
                    self,
                    CentrifugeUnsubscribeEvent()
                )
            }
        }
    }
}
