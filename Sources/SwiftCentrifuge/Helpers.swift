//
//  Helpers.swift
//  SwiftCentrifuge
//
//  Created by Alexander Emelin on 05/01/2019.
//  Copyright © 2019 Alexander Emelin. All rights reserved.
//

import Foundation
import SwiftProtobuf

struct CentrifugeDisconnectOptions: Decodable {
    var reason: String
    var reconnect: Bool
}

struct CentrifugeResolveData {
    var error: Error?
    var reply: Centrifugal_Centrifuge_Protocol_Reply?
}

struct StreamPosition {
    var offset: UInt64 = 0
    var epoch: String = ""
}

internal enum CentrifugeSerializer {
    static func serializeCommands(commands: [Centrifugal_Centrifuge_Protocol_Command]) throws -> Data {
        let stream = OutputStream.toMemory()
        stream.open()
        for command in commands {
            try BinaryDelimited.serialize(message: command, to: stream)
        }
        stream.close()
        return stream.property(forKey: .dataWrittenToMemoryStreamKey) as! Data
    }
    
    static func deserializeCommands(data: Data) throws -> [Centrifugal_Centrifuge_Protocol_Reply] {
        var commands = [Centrifugal_Centrifuge_Protocol_Reply]()
        let stream = InputStream(data: data as Data)
        stream.open()
        while true {
            do {
                let res = try BinaryDelimited.parse(messageType: Centrifugal_Centrifuge_Protocol_Reply.self, from: stream)
                commands.append(res)
            } catch BinaryDelimited.Error.truncated {
                // End of stream
                break
            }
        }
        return commands
    }
}
