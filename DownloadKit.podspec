Pod::Spec.new do |spec|

  spec.name         = "DownloadKit"
  spec.version      = "0.0.1"
  spec.summary      = "A short description of DownloadKit."
  spec.description  = <<-DESC
  DownloadKit is a framework that helps you manage your downloads.
                   DESC

  spec.homepage     = "https://github.com/blubblub/downloadkit-ios"
  spec.license      = "MIT"
  spec.author       = { "Jure Lajlar" => "jlajlar@gmail.com" }

  spec.platform     = :ios
  spec.platform     = :ios, "13.0"

  spec.source       = { :git => "git@github.com:blubblub/downloadkit-ios.git", :tag => "#{spec.version}" }

  spec.source_files  = "Sources/**/*.{h,m,swift}"

  spec.dependency "RealmSwift"

end
