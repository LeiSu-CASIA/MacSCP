import Foundation
import CryptoKit
final class TransferResume {
 let source:String;let destination:String;let upload:Bool;let temporaryPath:String
 private let lock=NSLock();private var digestValue:String?;private var signatureValue:String?;private var publicationValue:FTPPublicationRecord?;var onChange:(()->Void)?;var publicationBarrier:(()throws->Void)?;var beforePublication:(()throws->Void)?
 var ftpPublication:FTPPublicationRecord?{get{lock.lock();defer{lock.unlock()};return publicationValue}set{lock.lock();publicationValue=newValue;lock.unlock();onChange?()}}
 var sourceDigest:String?{get{lock.lock();defer{lock.unlock()};return digestValue}set{lock.lock();digestValue=newValue;lock.unlock();onChange?()}}
 var remoteSignature:String?{get{lock.lock();defer{lock.unlock()};return signatureValue}set{lock.lock();signatureValue=newValue;lock.unlock();onChange?()}}
 func persistPublication(_ record:FTPPublicationRecord)throws{ftpPublication=record;try publicationBarrier?()}
 func record()->ResumeRecord{lock.lock();defer{lock.unlock()};return ResumeRecord(source:source,destination:destination,upload:upload,temporaryPath:temporaryPath,sourceDigest:digestValue,remoteSignature:signatureValue,ftpPublication:publicationValue)}
 init(record:ResumeRecord){source=record.source;destination=record.destination;upload=record.upload;temporaryPath=record.temporaryPath;digestValue=record.sourceDigest;signatureValue=record.remoteSignature;publicationValue=record.ftpPublication}
 init(source:String,destination:String,upload:Bool){self.source=source;self.destination=destination;self.upload=upload;temporaryPath=upload ? destination+".macscp-resume-"+UUID().uuidString : URL(fileURLWithPath:destination).deletingLastPathComponent().appendingPathComponent(".macscp-resume-"+UUID().uuidString).path}
 static func digest(_ url:URL,checkpoint:(()throws->Void)?=nil)throws->String{let file=try FileHandle(forReadingFrom:url);defer{try? file.close()};var hash=SHA256();while let chunk=try file.read(upToCount:1024*1024),!chunk.isEmpty{try checkpoint?();hash.update(data:chunk)};return hash.finalize().map{String(format:"%02x",$0)}.joined()}
}
