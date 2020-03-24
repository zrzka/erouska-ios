//
//  ScannerStore.swift
//  BT-Tracking
//
//  Created by Tomas Svoboda on 18/03/2020.
//  Copyright © 2020 Covid19CZ. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import RxRealm
import RealmSwift

private let scanningPeriod = 60
private let scanningDelay = 0

final class ScannerStore {
    
    let currentScan = BehaviorRelay<[Scan]>(value: [])
    let scans: Observable<[Scan]>
    
    private let scanObjects: Results<ScanRealm>
    private let bag = DisposeBag()
    
    private let didFindSubject = PublishRelay<BTDevice>()
    private let didUpdateSubject = PublishRelay<BTDevice>()
    private let didReceive: Observable<BTDevice>
    private let timer: Observable<Int> = Observable.timer(.seconds(scanningDelay), period: .seconds(scanningPeriod), scheduler: ConcurrentDispatchQueueScheduler(qos: .background))
    private var period: BehaviorSubject<Void> {
        return BehaviorSubject<Void>(value: ())
    }
    private var currentPeriod: BehaviorSubject<Void>?
    private var devices = [BTDevice]()
    
    init() {
        didReceive = Observable.merge(didFindSubject.asObservable(), didUpdateSubject.asObservable())
        let realm = try! Realm()
        scanObjects = realm.objects(ScanRealm.self)
        scans = Observable.array(from: scanObjects)
            .map { scanned in
                return scanned.map { $0.toScan() }
            }
        bindScanning()
    }
    
    private func bindScanning() {
        // Periods
        currentPeriod = period
        bind(newPeriod: currentPeriod, endsAt: Date() + Double(scanningPeriod))
        timer
            .skip(1)
            .subscribe(onNext: { [weak self] _ in
                self?.currentPeriod?.onCompleted()
            })
            .disposed(by: bag)

        // Device scans
        didReceive
            .subscribe(onNext: { [weak self] device in
                self?.devices.append(device)
                self?.updateCurrent(at: Date())
            })
            .disposed(by: bag)
    }
    
    private func bind(newPeriod: BehaviorSubject<Void>?, endsAt endDate: Date) {
        newPeriod?
            .subscribe(onCompleted: { [unowned self] in
                self.currentPeriod = self.period
                self.bind(newPeriod: self.currentPeriod, endsAt: Date() + Double(scanningPeriod))
                self.process(self.devices, at: endDate)
                self.devices.removeAll()
            })
            .disposed(by: bag)
    }
    
    private func process(_ devices: [BTDevice], at date: Date) {
        let grouped = Dictionary(grouping: devices, by: { $0.deviceIdentifier })
        let averaged = grouped.map { group -> ScanRealm in
            guard var device = group.value.first,
                let backendIdentifier = group.value.first(where: { $0.backendIdentifier != nil })?.backendIdentifier,
                let startDate = group.value.first?.date,
                let endDate = group.value.last?.date else {
                    let empty = ScanRealm()
                    empty.buid = ""
                    return empty
            }

            device.backendIdentifier = backendIdentifier

            let RSIIs = group.value.map{ $0.rssi }
            let averageRssi = Int(RSIIs.average.rounded())
            var medianRssi: Int = 0
            if let median = RSIIs.median() {
                medianRssi = Int(median.rounded())
            }

            return ScanRealm(device: device, avargeRssi: averageRssi, medianRssi: medianRssi, startDate: startDate, endDate: endDate)
        }

        let data = averaged.filter() { $0.buid != "" }
        data.forEach { addDeviceToStorage(data: $0) }
    }
    
    private func updateCurrent(at date: Date) {
        let grouped = Dictionary(grouping: devices, by: { $0.deviceIdentifier })
        let latestDevices = grouped
            .map { group -> BTDevice? in
                let sorted = group.value.sorted(by: { $0.date > $1.date })
                var last = sorted.last
                last?.date = date
                return last
            }
            .compactMap{ $0 }
            .map { [unowned self] device -> Scan in
                let uuid = self.currentScan.value.first(where: { $0.deviceIdentifier == device.deviceIdentifier })?.id
                return device.toScan(with: uuid)
            }
        currentScan.accept(latestDevices)
    }
    
    private func addDeviceToStorage(data: ScanRealm) {
        do {
            let realm = try Realm()
            try realm.write {
                realm.add(data, update: .all)
            }
        } catch {
            log("Realm: Failed to write! \(error)")
        }
    }

}

extension ScannerStore: BTScannerDelegate {

    func didFind(device: BTDevice) {
        didFindSubject.accept(device)
    }

    func didUpdate(device: BTDevice) {
        didUpdateSubject.accept(device)
    }

}

extension ScannerStore {
    
    func clear() {
        let realm = try! Realm()
        try! realm.write {
            realm.deleteAll()
        }
    }
}
