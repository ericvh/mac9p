import Foundation

public enum NineP {
    public enum Version: String, CaseIterable {
        case v2000 = "9P2000"
        case v2000u = "9P2000.u"
        case v2000L = "9P2000.L"
    }

    /// 9P message types (subset used for read-only MVP).
    public enum MsgType: UInt8 {
        case tversion = 100
        case rversion = 101
        case tauth = 102
        case rauth = 103
        case tattach = 104
        case rattach = 105
        case rerror = 107
        case twalk = 110
        case rwalk = 111
        case topen = 112
        case ropen = 113
        case tread = 116
        case rread = 117
        case tclunk = 120
        case rclunk = 121
        case tstat = 124
        case rstat = 125
    }

    public struct Qid: Equatable, Sendable {
        public var type: UInt8
        public var vers: UInt32
        public var path: UInt64
    }

    public struct Stat: Equatable, Sendable {
        public var qid: Qid
        public var mode: UInt32
        public var atime: UInt32
        public var mtime: UInt32
        public var length: UInt64
        public var name: String
        public var uid: String
        public var gid: String
        public var muid: String
    }
}

