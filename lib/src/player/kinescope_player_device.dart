// Copyright (c) 2021-present, Kinescope
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../data/player_status.dart';
import '../data/player_time_update.dart';
import '../kinescope_player_controller.dart';
import '../utils/uri_builder.dart';

const _scheme = 'https';
const _kinescopeUri = 'kinescope.io';

class KinescopePlayerDevice extends StatefulWidget {
  final KinescopePlayerController controller;

  /// Aspect ratio for the player,
  /// by default it's 16 / 9.
  final double aspectRatio;

  /// A widget to play Kinescope videos.
  const KinescopePlayerDevice({
    super.key,
    required this.controller,
    this.aspectRatio = 16 / 9,
  });

  @override
  State<KinescopePlayerDevice> createState() => _KinescopePlayerState();
}

class _KinescopePlayerState extends State<KinescopePlayerDevice> {
  late PlatformWebViewController controller;

  Completer<Duration>? getCurrentTimeCompleter;

  Completer<Duration>? getDurationCompleter;
  Completer<double>? getPlaybackRateCompleter;
  Completer<bool>? getIsPausedCompleter;

  late String videoId;
  late String externalId;
  late String baseUrl;
  late String baseHost;

  @override
  void initState() {
    super.initState();
    videoId = widget.controller.videoId;
    externalId = widget.controller.parameters.externalId ?? '';
    baseUrl = widget.controller.parameters.baseUrl ??
        Uri(
          scheme: _scheme,
          host: _kinescopeUri,
        ).toString();
    baseHost = Uri.parse(baseUrl).host;

    late final PlatformWebViewControllerCreationParams params;

    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = PlatformWebViewController(params);

    // ignore: cascade_invocations
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setPlatformNavigationDelegate(
        PlatformNavigationDelegate(
          const PlatformNavigationDelegateCreationParams(),
        )
          ..setOnNavigationRequest((request) {
            if (!request.url.contains(_kinescopeUri) &&
                !request.url.contains(baseHost)) {
              debugPrint('blocking navigation to ${request.url}');
              return NavigationDecision.prevent;
            }
            debugPrint('allowing navigation to ${request.url}');
            return NavigationDecision.navigate;
          })
          ..setOnUrlChange(
            (change) {
              debugPrint('url change to ${change.url}');
            },
          ),
      )
      ..addJavaScriptChannel(
        JavaScriptChannelParams(
          name: 'Events',
          onMessageReceived: (message) {
            if (!widget.controller.statusController.isClosed) {
              widget.controller.statusController.add(
                KinescopePlayerStatus.values.firstWhere(
                  (value) => value.toString() == message.message,
                  orElse: () => KinescopePlayerStatus.unknown,
                ),
              );
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        JavaScriptChannelParams(
          name: 'CurrentTime',
          onMessageReceived: (message) {
            final dynamic seconds = double.parse(message.message);
            if (seconds is num) {
              getCurrentTimeCompleter?.complete(
                Duration(milliseconds: (seconds * 1000).ceil()),
              );
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        JavaScriptChannelParams(
          name: 'Duration',
          onMessageReceived: (message) {
            final dynamic seconds = double.parse(message.message);
            if (seconds is num) {
              getDurationCompleter?.complete(
                Duration(milliseconds: (seconds * 1000).ceil()),
              );
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        JavaScriptChannelParams(
          name: 'PlayBackRate',
          onMessageReceived: (message) {
            final dynamic currentSpeed = double.parse(message.message);
            if (currentSpeed is num) {
              getPlaybackRateCompleter?.complete(currentSpeed.toDouble());
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        JavaScriptChannelParams(
          name: 'CheckPaused',
          onMessageReceived: (message) {
            final dynamic isPaused = bool.parse(message.message);
            if (isPaused is bool) {
              getIsPausedCompleter?.complete(isPaused);
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        JavaScriptChannelParams(
          name: 'PipChange',
          onMessageReceived: (message) {
            final dynamic isPip = bool.parse(message.message);
            if (isPip is bool) {
              widget.controller.onChangePip?.call(isPip);
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        JavaScriptChannelParams(
          name: 'PlaybackRateChange',
          onMessageReceived: (message) {
            final dynamic currentSpeed = message.message;
            if (currentSpeed is num) {
              widget.controller.onChangePlaybackRate?.call(
                currentSpeed.toDouble(),
              );
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        JavaScriptChannelParams(
          name: 'FullScreen',
          onMessageReceived: (message) {
            final dynamic isFullscreen = bool.parse(message.message);
            if (isFullscreen is bool) {
              widget.controller.onChangeFullscreen?.call(isFullscreen);
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        JavaScriptChannelParams(
          name: 'TimeUpdate',
          onMessageReceived: (message) {
            if (message.message.contains('currentTime')) {
              final data = jsonDecode(message.message) as Map<String, dynamic>;
              if (!widget.controller.timeUpdateController.isClosed) {
                widget.controller.timeUpdateController
                    .add(KinescopePlayerTimeUpdate.fromJson(data));
              }
            }
          },
        ),
      )
      ..setOnPlatformPermissionRequest(
        (request) {
          debugPrint(
            'requesting permissions for ${request.types.map((type) => type.name)}',
          );
          request.grant();
        },
      )
      ..setOnConsoleMessage((message) {
        debugPrint('js: ${message.message}');
      })
      ..setUserAgent(getUserArgent())
      ..loadHtmlString(_player, baseUrl: baseUrl);

    if (controller is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      controller.setMediaPlaybackRequiresUserGesture(false);
    }

    widget.controller.controllerProxy
      ..setLoadVideoCallback(_proxyLoadVideo)
      ..setPlayCallback(_proxyPlay)
      ..setPauseCallback(_proxyPause)
      ..setStopCallback(_proxyStop)
      ..setGetCurrentTimeCallback(_proxyGetCurrentTime)
      ..setGetDurationCallback(_proxyGetDuration)
      ..setGetPlayBackRateCallback(_proxyGetPlayBackRate)
      ..setGetIsPausedCallback(_proxyGetIsPausedCallback)
      ..setSeekToCallback(_proxySeekTo)
      ..setSetFullscreenCallback(_proxySetFullscreen)
      ..setSetVolumeCallback(_proxySetVolume)
      ..setMuteCallback(_proxyMute)
      ..setUnuteCallback(_proxyUnmute);

    this.controller = controller;
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  void _proxyLoadVideo(String videoId) {
    controller.runJavaScript(
      'loadVideo("$videoId");',
    );
  }

  void _proxyPlay() {
    controller.runJavaScript('play();');
  }

  void _proxyPause() {
    controller.runJavaScript('pause();');
  }

  void _proxyStop() {
    controller.runJavaScript('stop();');
  }

  Future<Duration> _proxyGetCurrentTime() async {
    getCurrentTimeCompleter = Completer<Duration>();

    await controller.runJavaScript(
      'getCurrentTime();',
    );

    final time = await getCurrentTimeCompleter?.future;

    return time ?? Duration.zero;
  }

  Future<Duration> _proxyGetDuration() async {
    getDurationCompleter = Completer<Duration>();

    await controller.runJavaScript(
      'getDuration();',
    );

    final duration = await getDurationCompleter?.future;

    return duration ?? Duration.zero;
  }

  Future<double> _proxyGetPlayBackRate() async {
    getPlaybackRateCompleter = Completer<double>();
    await controller.runJavaScript('getPlaybackRate();');
    final playBackRate = await getPlaybackRateCompleter?.future;
    return playBackRate ?? 1.0;
  }

  Future<bool> _proxyGetIsPausedCallback() async {
    getIsPausedCompleter = Completer<bool>();
    await controller.runJavaScript('isPaused();');
    final isPaused = await getIsPausedCompleter?.future;
    return isPaused ?? false;
  }

  void _proxySeekTo(Duration duration) {
    controller.runJavaScript(
      'seekTo(${duration.inSeconds});',
    );
  }

  void _proxySetVolume(double value) {
    controller.runJavaScript('setVolume($value);');
  }

  void _proxyMute() {
    controller.runJavaScript('mute();');
  }

  void _proxyUnmute() {
    controller.runJavaScript('unmute();');
  }

  void _proxySetFullscreen(bool value) {
    controller.runJavaScript('setFullscreen($value);');
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: PlatformWebViewWidget(
        PlatformWebViewWidgetCreationParams(controller: controller),
      ).build(context),
    );
  }

  String? getUserArgent() {
    return (Platform.isIOS
        ? 'Mozilla/5.0 (iPad; CPU iPhone OS 13_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) KinescopePlayerFlutter/0.2.3'
        : 'Mozilla/5.0 (Android 9.0; Mobile; rv:59.0) Gecko/59.0 Firefox/59.0 KinescopePlayerFlutter/0.2.3');
  }

  // ignore: member-ordering-extended
  String get _player => '''
<!DOCTYPE html>
<html>

<head>
    <meta charset="utf-8" />
    <meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no'>
    <style>
        html, body {
            padding: 0;
            margin: 0;
            width: 100%;
            height: 100%;
        }
        #player {
            position: fixed;
            width: 100%;
            height: 100%;
            left: 0;
            top: 0;
        }
    </style>

    <script>
        window.addEventListener("flutterInAppWebViewPlatformReady", function (event) {
            Events.postMessage('ready');
        });

        let kinescopePlayerFactory = null;

        let kinescopePlayer = null;

        let initialVideoUri = '${UriBuilder.buildVideoUri(videoId: videoId)}';

        function onKinescopeIframeAPIReady(playerFactory) {
            kinescopePlayerFactory = playerFactory;

            loadVideo(initialVideoUri);
        }

        function loadVideo(videoUri) {
            if (kinescopePlayer != null) {
                kinescopePlayer.destroy();
                kinescopePlayer = null;
            }

            if (kinescopePlayerFactory != null) {
                var devElement = document.createElement("div");
                devElement.id = "player";
                document.body.append(devElement);

                kinescopePlayerFactory
                    .create('player', {
                        url: videoUri,
                        size: { width: '100%', height: '100%' },
                        settings: {
                          externalId: '$externalId'
                        },
                        behaviour: {
                            ...${UriBuilder.parametersToBehavior(widget.controller.parameters)},
                            fullscreenFallback: '${widget.controller.parameters.fullscreenFallback.name}',
                        },
                        ui: ${UriBuilder.parametersToUI(widget.controller.parameters)}
                    })
                    .then(function (player) {
                        kinescopePlayer = player;
                        Events.postMessage('init');

                        player.once(player.Events.Ready, function (event) {
                          var time = ${UriBuilder.parameterSeekTo(widget.controller.parameters)};
                          if(time > 0 || time === 0) {
                             event.target.seekTo(time);
                          }
                        });
                        player.on(player.Events.Ready, function (event) { Events.postMessage('ready'); });
                        player.on(player.Events.Playing, function (event) { Events.postMessage('playing'); });
                        player.on(player.Events.Waiting, function (event) { Events.postMessage('waiting'); });
                        player.on(player.Events.Pause, function (event) { Events.postMessage('pause'); });
                        player.on(player.Events.Ended, function (event) { Events.postMessage('ended'); });
                        player.on(player.Events.FullscreenChange, onFullScreen);
                        player.on(player.Events.PlaybackRateChange, onPlaybackRateChange);
                        player.on(player.Events.PipChange, onPipChange);
                        player.on(player.Events.TimeUpdate, onTimeUpdate); 
                    });
            }
        }

        function play() {
            if (kinescopePlayer != null)
              kinescopePlayer.play();
        }

        function pause() {
            if (kinescopePlayer != null)
              kinescopePlayer.pause();
        }

        function stop() {
            if (kinescopePlayer != null)
              kinescopePlayer.stop();
        }

        function getCurrentTime() {
            if (kinescopePlayer != null)
              return kinescopePlayer.getCurrentTime();
        }

        function seekTo(seconds) {
            if (kinescopePlayer != null)
              kinescopePlayer.seekTo(seconds);
        }

        function getCurrentTime() {
            if (kinescopePlayer != null)
              kinescopePlayer.getCurrentTime().then((value) => {
                CurrentTime.postMessage(value);
              });
        }

        function getDuration() {
            if (kinescopePlayer != null)
              kinescopePlayer.getDuration().then((value) => {
                Duration.postMessage(value);
              });
        }
        
        function getPlaybackRate() {
            if (kinescopePlayer != null)
              kinescopePlayer.getPlaybackRate().then((value) => {
                  PlayBackRate.postMessage(value);
              });
        }
        
        function isPaused() {
            if (kinescopePlayer != null)
              kinescopePlayer.isPaused().then((value) => {
                 CheckPaused.postMessage(value);
              });
        }      

        function setVolume(value) {
            if (kinescopePlayer != null)
              kinescopePlayer.setVolume(value);
        }    
        
        function setFullscreen(value) {
            if (kinescopePlayer != null)
              kinescopePlayer.setFullscreen(value);
        }

        function mute() {
            if (kinescopePlayer != null)
              kinescopePlayer.mute();
        }

        function unmute() {
            if (kinescopePlayer != null)
              kinescopePlayer.unmute();
        }

        function onFullScreen(arg) {
            FullScreen.postMessage(arg.data.isFullscreen);           
        }  
        
        function onPipChange(arg) {
            PipChange.postMessage(arg.data.isPip);
        }
    
        function onPlaybackRateChange(arg) {
          PlaybackRateChange.postMessage(arg.data.playbackRate);
        }

        function onTimeUpdate(arg) {
          TimeUpdate.postMessage(JSON.stringify(arg.data));
        }
    </script>
</head>

<body>
    <script>
        var tag = document.createElement('script');

        tag.src = 'https://player.kinescope.io/latest/iframe.player.js';
        var firstScriptTag = document.getElementsByTagName('script')[0];
        firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);
    </script>
</body>

</html>
''';
}
