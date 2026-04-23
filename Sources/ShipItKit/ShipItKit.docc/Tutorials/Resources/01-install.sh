git clone https://github.com/shipitswifty/shipitswifty
cd shipitswifty
swift build -c release
sudo cp .build/release/shipit /usr/local/bin/shipit
