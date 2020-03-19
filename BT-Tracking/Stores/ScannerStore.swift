//
//  ScannerStore.swift
//  BT-Tracking
//
//  Created by Tomas Svoboda on 18/03/2020.
//  Copyright © 2020 Covid19CZ. All rights reserved.
//

import UIKit
import CoreBluetooth
import RxSwift
import RxCocoa

class ScannerStore: BTScannerStoreDelegate {
    
    let scans = BehaviorRelay<[Scan]>(value: [])
    
    func didFind(device: CBPeripheral, rssi: Int) {
        let scan = Scan(identifier: device.identifier.uuidString, name: device.name ?? "Unknown", date: Date(), rssi: rssi)
        let updatedScans = scans.value + [scan]
        scans.accept(updatedScans)
    }
}