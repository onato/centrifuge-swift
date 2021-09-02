0.4.0
=====

Update to work with Centrifuge >= v0.18.0 and Centrifugo v3.

**Breaking change** in server behavior. Client History API behavior changed in Centrifuge >= v0.18.0 and Centrifugo >= v3.0.0. When using history call it won't return all publications in a stream by default. See Centrifuge [v0.18.0 release notes](https://github.com/centrifugal/centrifuge/releases/tag/v0.18.0) or [Centrifugo v3 migration guide](https://centrifugal.dev/docs/getting-started/migration_v3) for more information and workaround on server-side.

* Protocol definitions updated to the latest version 
* History method now accepts optional `limit`, `since` and `reverse` arguments and returns `CentrifugeHistoryResult`
* presence now returns `CentrifugePresenceResult`
* presenceStats now returns `CentrifugePresenceStatsResult`
* Publish now returns `CentrifugePublishResult`
* When working with Centrifugo v3 or Centrifuge >= v0.18.0 it's now possible to avoid using `?format=protobuf` in connection URL. Client will negotiate Protobuf protocol with a server using WebSocket subprotocol mechanism (in request headers).

0.3.1
=====

* Fix internal error handling in subscription reply – now properly reconnect upon internal error received.

0.3.0
=====

* Message recovery support for client-side subscriptions. See [#39](https://github.com/centrifugal/centrifuge-swift/pull/39). Thanks to Anton Selyanin.

0.2.2
=====

* Add initial WebSocket reconnection delay (mitigating issues with Starscream connect timeout). Thanks to Anton Selyanin.

0.2.1
=====

* Fix refresh token task retain cycle [#38](https://github.com/centrifugal/centrifuge-swift/pull/38)

0.2.0
=====

A couple of new methods added to Client.

* `Client.getSubscription(channel: String) -> CentrifugeSubscription?` to get Subscription from internal client registry
* `Client.removeSubscription(_ sub: CentrifugeSubscription)` to tell Client that Subscription should be removed from internal registry. Subscription will be automatically unsubscribed before removing.

See more details in pull request [#36](https://github.com/centrifugal/centrifuge-swift/pull/36). In short, subscription removing can be helpful if you work with lots of short-living subscriptions to different channels to prevent unlimited internal Subscription registry growth.

0.1.0
=====

* Update client.proto file. Update sendRPC method - [#33](https://github.com/centrifugal/centrifuge-swift/pull/33), thanks [@hitman1711](https://github.com/hitman1711)

0.0.6
=====

* Public fields for `CentrifugePublication`, `CentrifugeClientInfo`, `CentrifugePresenceStats`

0.0.5
=====

* reduce access for private functions (#20)
* rewrite code to escape await logic (#23)
* Feature/subscription weak reference (#25)

0.0.4
=====

* Mark `refresh` and `private sub` completion blocks as escaping
* Fix Starscream dependency to compatible version

0.0.3
=====

* fix client deinit (#10)
* fix unlock issue (#11)
* add SPM product (library) and update dependencies (#15)

0.0.2
=====

* refactor library layout
* fix extensions and subscription channel property access levels.
* Travis CI setup

0.0.1
=====

Initial library release.
