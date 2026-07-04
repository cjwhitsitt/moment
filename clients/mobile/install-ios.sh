#!/bin/zsh

fvm flutter build ipa
for device in $(ios-deploy -c | grep "Found" | cut -d "'" -f 2); do
  ios-deploy --id "$device" --bundle build/ios/ipa/moment.ipa &
done
wait
