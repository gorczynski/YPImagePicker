//
//  YPImagePicker.swift
//  YPImgePicker
//
//  Created by Sacha Durand Saint Omer on 27/10/16.
//  Copyright © 2016 Yummypets. All rights reserved.
//

import UIKit
import AVFoundation

public class YPImagePicker: UINavigationController {
    
    public var didSelectImage: ((UIImage) -> Void)?
    public var didSelectVideo: ((Data, UIImage, URL) -> Void)?
    public var didSelectItems: (([YPMediaItem]) -> Void)?
    public var didCancel: (() -> Void)?
    
    // This nifty little trick enables us to call the single version of the callbacks.
    // This keeps the backwards compatibility keeps the api as simple as possible.
    // Multiple selection becomes available as an opt-in.
    private func didSelect(items: [YPMediaItem]) -> Void {
        if items.count == 1 {
            if let didSelectImage = didSelectImage, let first = items.first, case let .photo(pickedPhoto) = first {
                didSelectImage(pickedPhoto.image)
            } else if let didSelectVideo = didSelectVideo, let first = items.first, case let .video(pickedVideo) = first {
                pickedVideo.fetchData { videoData in
                    didSelectVideo(videoData, pickedVideo.thumbnail, pickedVideo.url)
                }
            }
        } else {
            didSelectItems?(items)
        }
    }
    
    let loadingView = YPLoadingView()
    private let picker: YPPickerVC!
    
    /// Get a YPImagePicker instance with the default configuration.
    public convenience init() {
        self.init(configuration: YPImagePickerConfiguration.shared)
    }
    
    /// Get a YPImagePicker with the specified configuration.
    public required init(configuration: YPImagePickerConfiguration) {
        YPImagePickerConfiguration.shared = configuration
        picker = YPPickerVC()
        super.init(nibName: nil, bundle: nil)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        picker.didClose = didCancel
        viewControllers = [picker]
        setupLoadingView()
        navigationBar.isTranslucent = false

        picker.didSelectItems = { [unowned self] items in
            let showsFilters = YPConfig.showsFilters
            
            // Use Fade transition instead of default push animation
            let transition = CATransition()
            transition.duration = 0.3
            transition.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
            transition.type = kCATransitionFade
            self.view.layer.add(transition, forKey: nil)
            
            // Multiple items flow
            if items.count > 1 {
                let selectionsGalleryVC = YPSelectionsGalleryVC.initWith(items: items)
                selectionsGalleryVC.didFinishWithItems = { items in
                    self.didSelect(items: items)
                }
                self.pushViewController(selectionsGalleryVC, animated: true)
                return
            }
            
            // One item flow
            let item = items.first!
            
            switch item {
            case .photo(let photo):
                
                let completion = { (photo: YPMediaPhoto) in
                    let mediaItem = YPMediaItem.photo(p: photo)
                    // Save new image to the photo album.
                    if YPConfig.shouldSaveNewPicturesToAlbum, let modifiedImage = photo.modifiedImage {
                        YPPhotoSaver.trySaveImage(modifiedImage, inAlbumNamed: YPConfig.albumName)
                    }
                    self.didSelect(items: [mediaItem])
                }
                
                func showCropVC(photo: YPMediaPhoto, completion: @escaping (_ aphoto: YPMediaPhoto) -> Void) {
                    if case let YPCropType.rectangle(ratio) = YPConfig.showsCrop {
                        let cropVC = YPCropVC(image: photo.image, ratio: ratio)
                        cropVC.didFinishCropping = { croppedImage in
                            photo.modifiedImage = croppedImage
                            completion(photo)
                        }
                        self.pushViewController(cropVC, animated: true)
                    } else {
                        completion(photo)
                    }
                }
                
                if showsFilters {
                    let filterVC = YPPhotoFiltersVC(inputPhoto: photo,
                                                    isFromSelectionVC: false)
                    // Show filters and then crop
                    filterVC.didSave = { outputMedia in
                        if case let YPMediaItem.photo(outputPhoto) = outputMedia {
                            showCropVC(photo: outputPhoto, completion: completion)
                        }
                    }
                    self.pushViewController(filterVC, animated: false)
                } else {
                    showCropVC(photo: photo, completion: completion)
                }
            case .video(let video):
                if showsFilters {
                    let videoFiltersVC = YPVideoFiltersVC.initWith(video: video,
                                                                   isFromSelectionVC: false)
                    videoFiltersVC.didSave = { [unowned self] outputMedia in
                        self.didSelect(items: [outputMedia])
                    }
                    self.pushViewController(videoFiltersVC, animated: true)
                } else {
                    self.didSelect(items: [YPMediaItem.video(v: video)])
                }
            }
        }
    }
    
    private func setupLoadingView() {
        view.sv(
            loadingView
        )
        loadingView.fillContainer()
        loadingView.alpha = 0
    }
}
