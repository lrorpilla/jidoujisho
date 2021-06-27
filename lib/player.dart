import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:clipboard_monitor/clipboard_monitor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jidoujisho/main.dart';
import 'package:progress_indicators/progress_indicators.dart';

import 'package:jidoujisho/cache.dart';
import 'package:jidoujisho/dictionary.dart';
import 'package:jidoujisho/globals.dart';
import 'package:jidoujisho/pitch.dart';
import 'package:jidoujisho/preferences.dart';
import 'package:ve_dart/ve_dart.dart';

class Reader extends StatefulWidget {
  @override
  State<Reader> createState() => ReaderState();
}

class ReaderState extends State<Reader> {
  ReaderState();

  final _clipboard = ValueNotifier<String>("");
  final _currentDictionaryEntry =
      ValueNotifier<DictionaryEntry>(DictionaryEntry(
    word: "",
    reading: "",
    meaning: "",
  ));
  int initialPosition;
  String _volatileText = "";
  String highlightedText = "";
  FocusNode _subtitleFocusNode = new FocusNode();
  List<String> recursiveTerms = [];
  bool noPush = false;

  Timer durationTimer;
  Timer visibilityTimer;

  InAppWebViewController webViewController;
  InAppWebViewGroupOptions options = InAppWebViewGroupOptions(
      crossPlatform: InAppWebViewOptions(
        useShouldOverrideUrlLoading: true,
        mediaPlaybackRequiresUserGesture: false,
      ),
      android: AndroidInAppWebViewOptions(
        useHybridComposition: true,
      ),
      ios: IOSInAppWebViewOptions(
        allowsInlineMediaPlayback: true,
      ));
  ContextMenu contextMenu;

  @override
  void dispose() {
    stopAllClipboardMonitoring();
    super.dispose();
  }

  Future<void> clearSelection() async {
    String clearJs = "window.getSelection().removeAllRanges();";

    await webViewController.evaluateJavascript(source: clearJs);
  }

  void startClipboardMonitor() {
    ClipboardMonitor.registerCallback(onClipboardText);
  }

  void stopClipboardMonitor() {
    ClipboardMonitor.unregisterCallback(onClipboardText);
  }

  void onClipboardText(String text) {
    text = text.trim();
    _volatileText = text.trim();

    Future.delayed(
        text.length == 1
            ? Duration(milliseconds: 1000)
            : Duration(milliseconds: 500), () {
      if (_volatileText.trim() == text.trim()) {
        _clipboard.value = text;
      }
    });
  }

  String textClickJs = """
/*jshint esversion: 6 */
var touchmoved;
var touchevent;
var reader = document.getElementsByTagName('app-reader')[0];

reader.addEventListener('touchend', function() {
	if (touchmoved !== true) {
		var touch = touchevent.touches[0];
		var result = document.caretRangeFromPoint(touch.clientX, touch.clientY);
		var selectedElement = result.startContainer;

    var paragraph = result.startContainer;
    while (paragraph && paragraph.nodeName !== 'P') {
      console.log(paragraph.nodeName);
      paragraph = paragraph.parentNode;
    }

    console.log(paragraph.nodeName);

		var noFuriganaText = [];
		var noFuriganaNodes = [];
		var selectedFound = false;
		var index = 0;

		for (var value of paragraph.childNodes.values()) {
			if (value.nodeName === "#text") {
				noFuriganaText.push(value.textContent);
				noFuriganaNodes.push(value);

				if (selectedFound === false) {
					if (selectedElement !== value) {
						index = index + value.textContent.length;
					} else {
						index = index + result.startOffset;
						selectedFound = true;
					}
				}

			} else {
				for (var node of value.childNodes.values()) {
					if (node.nodeName === "#text") {
						noFuriganaText.push(node.textContent);
						noFuriganaNodes.push(node);

						if (selectedFound === false) {
							if (selectedElement !== node) {
								index = index + node.textContent.length;
							} else {
								index = index + result.startOffset;
								selectedFound = true;
							}
						}
					} else if (node.firstChild.nodeName === "#text" && node.nodeName !== "RT" && node.nodeName !== "RP") {
						noFuriganaText.push(node.firstChild.textContent);
						noFuriganaNodes.push(node.firstChild);

						if (selectedFound === false) {
							if (selectedElement !== node.firstChild) {
								index = index + node.firstChild.textContent.length;
							} else {
								index = index + result.startOffset;
								selectedFound = true;
							}
						}
					}
				}
			}
		}

		var text = noFuriganaText.join("");
		var offset = index;

		if (result.startContainer.innerHTML == null ||
        result.startContainer.innerHTML.innerHTML.indexOf("spoiler-label") === -1) {
			console.log(JSON.stringify({
				"offset": offset,
				"text": text,
				"jidoujisho": "jidoujisho"
			}));
		}
	}
});
reader.addEventListener('touchmove', () => {
	touchmoved = true;
	touchevent = null;
});
reader.addEventListener('touchstart', (e) => {
	touchmoved = false;
	touchevent = e;
});
""";

  @override
  Widget build(BuildContext context) {
    startClipboardMonitor();

    contextMenu = ContextMenu(
        options: ContextMenuOptions(hideDefaultSystemContextMenuItems: true),
        menuItems: [
          ContextMenuItem(
              androidId: 1,
              iosId: "1",
              title: "A⌕",
              action: () async {
                emptyStack();
                await useBilingual();
                _clipboard.value = (await webViewController.getSelectedText())
                        .replaceAll("\\n", "\n")
                        .trim() ??
                    "";
                clearSelection();
              }),
          ContextMenuItem(
              androidId: 2,
              iosId: "2",
              title: "あ⌕",
              action: () async {
                emptyStack();
                await useMonolingual();
                _clipboard.value = (await webViewController.getSelectedText())
                        .replaceAll("\\n", "\n")
                        .trim() ??
                    "";
                clearSelection();
              }),
          ContextMenuItem(
              androidId: 3,
              iosId: "3",
              title: "Creator",
              action: () async {
                emptyStack();

                String readerExport =
                    await webViewController.getSelectedText() ?? "";
                print(readerExport);

                stopClipboardMonitor();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Home(readerExport: readerExport),
                  ),
                ).then((result) {
                  SystemChrome.setEnabledSystemUIOverlays([]);
                  _clipboard.value = "";
                  startClipboardMonitor();
                });

                clearSelection();
              }),
        ],
        onCreateContextMenu: (result) {
          _clipboard.value = "";
        },
        onContextMenuActionItemClicked: (menuItem) {
          var id = (Platform.isAndroid) ? menuItem.androidId : menuItem.iosId;
        });

    return new WillPopScope(
      onWillPop: () async {
        Widget alertDialog = AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          title: new Text('Exit Reader?'),
          actions: <Widget>[
            new TextButton(
              child: Text(
                'NO',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: TextButton.styleFrom(
                textStyle: TextStyle(
                  color: Colors.white,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            new TextButton(
              child: Text(
                'YES',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: TextButton.styleFrom(
                textStyle: TextStyle(
                  color: Colors.white,
                ),
              ),
              onPressed: () async {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
          ],
        );

        return (await showDialog(
              context: context,
              builder: (context) => alertDialog,
            )) ??
            false;
      },
      child: new Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.black,
        body: Stack(
          alignment: Alignment.topCenter,
          children: [
            InAppWebView(
              initialUrlRequest:
                  URLRequest(url: Uri.parse("https://ttu-ebook.web.app/")),
              initialOptions: options,
              androidOnPermissionRequest:
                  (controller, origin, resources) async {
                return PermissionRequestResponse(
                    resources: resources,
                    action: PermissionRequestResponseAction.GRANT);
              },
              contextMenu: contextMenu,
              onConsoleMessage: (controller, consoleMessage) {
                print(consoleMessage);

                Map<String, dynamic> messageJson =
                    jsonDecode(consoleMessage.message);

                if (messageJson["jidoujisho"] == "jidoujisho") {
                  emptyStack();

                  int index = messageJson["offset"];
                  String text = messageJson["text"];

                  try {
                    String processedText = text.replaceAll("﻿", "␝");
                    processedText = processedText.replaceAll("　", "␝");
                    processedText = processedText.replaceAll('\n', '␜');
                    processedText = processedText.replaceAll(' ', '␝');

                    List<Word> tokens = parseVe(gMecabTagger, processedText);
                    print(tokens);

                    List<String> tokenTape = [];
                    for (int i = 0; i < tokens.length; i++) {
                      Word token = tokens[i];
                      for (int j = 0; j < token.word.length; j++) {
                        tokenTape.add(token.word);
                      }
                    }

                    // print(tokenTape);
                    String searchTerm = tokenTape[index];
                    searchTerm = searchTerm.replaceAll('␜', '\n');
                    searchTerm = searchTerm.replaceAll('␝', ' ');
                    searchTerm = searchTerm.trim();
                    print("SELECTED: " + searchTerm);
                    // print("reached");

                    clearSelection();
                    _clipboard.value = searchTerm;
                  } catch (e) {
                    clearSelection();
                    emptyStack();
                    _clipboard.value = "";
                    print(e);
                  }
                }
              },
              onWebViewCreated: (controller) {
                webViewController = controller;
              },
              onLoadStop: (controller, url) async {
                await controller.evaluateJavascript(source: textClickJs);
              },
              onTitleChanged: (controller, title) async {
                await controller.evaluateJavascript(source: textClickJs);
              },
            ),
            Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).size.height * 0.05,
                bottom: MediaQuery.of(context).size.height * 0.05,
              ),
              child: buildDictionary(),
            ),
          ],
        ),
      ),
    );
  }

  void emptyStack() {
    noPush = false;
    recursiveTerms = [];
  }

  void setNoPush() {
    noPush = true;
  }

  void stopAllClipboardMonitoring() {
    ClipboardMonitor.unregisterAllCallbacks();
  }

  Widget buildDictionaryLoading(String clipboard) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16.0),
          child: Container(
            padding: EdgeInsets.all(16.0),
            color: Colors.grey[600].withOpacity(0.97),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  "Looking up",
                  style: TextStyle(),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      "『",
                      style: TextStyle(
                        color: Colors.grey[300],
                      ),
                    ),
                    Text(
                      clipboard,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "』",
                      style: TextStyle(
                        color: Colors.grey[300],
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  height: 12,
                  width: 12,
                  child: JumpingDotsProgressIndicator(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: Container()),
      ],
    );
  }

  Widget buildDictionaryExporting(String clipboard) {
    String lookupText = "Preparing to export";

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16.0),
          child: Container(
            padding: EdgeInsets.all(16.0),
            color: Colors.grey[600].withOpacity(0.97),
            child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(lookupText),
                  SizedBox(
                    height: 12,
                    width: 12,
                    child: JumpingDotsProgressIndicator(color: Colors.white),
                  ),
                ]),
          ),
        ),
        Expanded(child: Container()),
      ],
    );
  }

  Widget buildDictionaryAutoGenDependencies(String clipboard) {
    String lookupText = "Setting up required dependencies";

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16.0),
          child: Container(
            padding: EdgeInsets.all(16.0),
            color: Colors.grey[600].withOpacity(0.97),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(lookupText),
                SizedBox(
                  height: 12,
                  width: 12,
                  child: JumpingDotsProgressIndicator(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: Container()),
      ],
    );
  }

  Widget buildDictionaryNetworkSubtitlesBad(String clipboard) {
    String lookupText = "Unable to query subtitles over network stream.";
    Future.delayed(Duration(seconds: 1), () {
      _clipboard.value = "";
    });

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16.0),
          child: Container(
            padding: EdgeInsets.all(16.0),
            color: Colors.grey[600].withOpacity(0.97),
            child: Text(lookupText),
          ),
        ),
        Expanded(child: Container()),
      ],
    );
  }

  Widget buildDictionaryNetworkSubtitlesRequest(String clipboard) {
    String lookupText = "Requesting subtitles over network stream";

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16.0),
          child: Container(
            padding: EdgeInsets.all(16.0),
            color: Colors.grey[600].withOpacity(0.97),
            child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(lookupText),
                  SizedBox(
                    height: 12,
                    width: 12,
                    child: JumpingDotsProgressIndicator(color: Colors.white),
                  ),
                ]),
          ),
        ),
        Expanded(child: Container()),
      ],
    );
  }

  Widget buildDictionaryAutoGenBad(String clipboard) {
    String lookupText = "Unable to query for automatic captions.";
    Future.delayed(Duration(seconds: 1), () {
      _clipboard.value = "";
    });

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16.0),
          child: Container(
            padding: EdgeInsets.all(16.0),
            color: Colors.grey[600].withOpacity(0.97),
            child: Text(lookupText),
          ),
        ),
        Expanded(child: Container()),
      ],
    );
  }

  Widget buildDictionaryAutoGenQuery(String clipboard) {
    String lookupText = "Querying for automatic captions";

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16.0),
          child: Container(
            padding: EdgeInsets.all(16.0),
            color: Colors.grey[600].withOpacity(0.97),
            child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(lookupText),
                  SizedBox(
                    height: 12,
                    width: 12,
                    child: JumpingDotsProgressIndicator(color: Colors.white),
                  ),
                ]),
          ),
        ),
        Expanded(child: Container()),
      ],
    );
  }

  Widget buildDictionaryExported(String clipboard) {
    String deckName = clipboard.substring(12, clipboard.length - 4);
    String lookupText = "Card exported to \"$deckName\".";

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16.0),
          child: Container(
            padding: EdgeInsets.all(16.0),
            color: Colors.grey[600].withOpacity(0.97),
            child: Text(lookupText),
          ),
        ),
        Expanded(child: Container()),
      ],
    );
  }

  Widget buildDictionaryNoMatch(String clipboard) {
    if (getMonolingualMode()) {
      gMonolingualSearchCache[clipboard] = null;
    } else {
      gBilingualSearchCache[clipboard] = null;
    }

    _subtitleFocusNode.unfocus();

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16.0),
          child: InkWell(
            onTap: () {
              _clipboard.value = "";
              _currentDictionaryEntry.value = DictionaryEntry(
                word: "",
                reading: "",
                meaning: "",
              );
            },
            child: Container(
                padding: EdgeInsets.all(16.0),
                color: Colors.grey[600].withOpacity(0.97),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      "No matches for",
                      style: TextStyle(),
                    ),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          "『",
                          style: TextStyle(
                            color: Colors.grey[300],
                          ),
                        ),
                        SelectableText(
                          clipboard,
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          "』",
                          style: TextStyle(
                            color: Colors.grey[300],
                          ),
                        ),
                      ],
                    ),
                    Text(
                      "could be queried.",
                      style: TextStyle(),
                    ),
                  ],
                )),
          ),
        ),
        Expanded(child: Container()),
      ],
    );
  }

  Widget buildDictionaryMatch(DictionaryHistoryEntry results) {
    if (noPush) {
      noPush = false;
    } else if (recursiveTerms.isEmpty ||
        results.searchTerm != recursiveTerms.last) {
      recursiveTerms.add(results.searchTerm);
    }

    _subtitleFocusNode.unfocus();
    ValueNotifier<int> selectedIndex = ValueNotifier<int>(0);

    return ValueListenableBuilder(
      valueListenable: selectedIndex,
      builder: (BuildContext context, int _, Widget widget) {
        _currentDictionaryEntry.value = results.entries[selectedIndex.value];
        DictionaryEntry pitchEntry =
            getClosestPitchEntry(_currentDictionaryEntry.value);
        ScrollController scrollController = ScrollController();

        addDictionaryEntryToHistory(
          DictionaryHistoryEntry(
            entries: results.entries,
            searchTerm: results.searchTerm,
            swipeIndex: selectedIndex.value,
            contextDataSource: results.contextDataSource,
            contextPosition: results.contextPosition,
          ),
        );

        return Container(
          padding: EdgeInsets.all(16.0),
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () {
              _clipboard.value = "";
              _currentDictionaryEntry.value = DictionaryEntry(
                word: "",
                reading: "",
                meaning: "",
              );
            },
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity == 0) return;

              if (details.primaryVelocity.compareTo(0) == -1) {
                if (selectedIndex.value == results.entries.length - 1) {
                  selectedIndex.value = 0;
                } else {
                  selectedIndex.value += 1;
                }
              } else {
                if (selectedIndex.value == 0) {
                  selectedIndex.value = results.entries.length - 1;
                } else {
                  selectedIndex.value -= 1;
                }
              }
            },
            child: Container(
              padding: EdgeInsets.all(16),
              color: Colors.grey[600].withOpacity(0.97),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onLongPress: () {
                      toggleMonolingualMode();
                      final String clipboardMemory = _clipboard.value;
                      _clipboard.value = "";
                      setNoPush();
                      _clipboard.value = clipboardMemory;
                    },
                    child: Text(
                      results.entries[selectedIndex.value].word,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  SizedBox(height: 5),
                  GestureDetector(
                    onLongPress: () {
                      toggleMonolingualMode();
                      final String clipboardMemory = _clipboard.value;
                      _clipboard.value = "";
                      setNoPush();
                      _clipboard.value = clipboardMemory;
                    },
                    child: (pitchEntry != null)
                        ? getAllPitchWidgets(pitchEntry)
                        : Text(results.entries[selectedIndex.value].reading),
                  ),
                  Flexible(
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: getMonolingualMode()
                            ? SelectableText(
                                "\n${results.entries[selectedIndex.value].meaning}\n",
                                style: TextStyle(
                                  fontSize: 15,
                                ),
                                toolbarOptions: ToolbarOptions(
                                    copy: true,
                                    cut: false,
                                    selectAll: false,
                                    paste: false),
                              )
                            : Text(
                                "\n${results.entries[selectedIndex.value].meaning}\n",
                                style: TextStyle(
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.center,
                    children: [
                      Text(
                        "Selecting search result ",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[300],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        "${selectedIndex.value + 1} ",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        "out of ",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[300],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        "${results.entries.length} ",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        "found for",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[300],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            "『",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.grey[300],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            "${results.searchTerm}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                            softWrap: true,
                          ),
                          Text(
                            "』",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.grey[300],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ],
                  ),
                  (recursiveTerms.length > 1)
                      ? GestureDetector(
                          onTap: () {
                            noPush = true;
                            recursiveTerms.removeLast();
                            _clipboard.value = recursiveTerms.last;
                          },
                          child: Padding(
                            padding: EdgeInsets.only(top: 8, bottom: 8),
                            child: Wrap(
                              alignment: WrapAlignment.start,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  "『 ",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.grey[300],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                Icon(Icons.arrow_back, size: 11),
                                SizedBox(width: 5),
                                Text(
                                  "Return to previous definition",
                                  style: TextStyle(
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                Text(
                                  " 』",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.grey[300],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : SizedBox.shrink(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future dictionaryFutureHelper(String clipboard) {
    if (getMonolingualMode()) {
      return fetchMonolingualSearchCache(
        searchTerm: clipboard,
        recursive: false,
        contextDataSource: "-1",
        contextPosition: -1,
      );
    } else {
      return fetchBilingualSearchCache(
        searchTerm: clipboard,
        contextDataSource: "-1",
        contextPosition: -1,
      );
    }
  }

  Widget buildDictionary() {
    return ValueListenableBuilder(
      valueListenable: _clipboard,
      builder: (context, clipboard, widget) {
        return FutureBuilder(
          future: dictionaryFutureHelper(clipboard),
          builder: (BuildContext context, AsyncSnapshot snapshot) {
            if (_clipboard.value == "&<&>export&<&>") {
              return buildDictionaryExporting(clipboard);
            }
            if (_clipboard.value == "&<&>autogen&<&>") {
              return buildDictionaryAutoGenQuery(clipboard);
            }
            if (_clipboard.value == "&<&>autogendependencies&<&>") {
              return buildDictionaryAutoGenDependencies(clipboard);
            }
            if (_clipboard.value == "&<&>autogenbad&<&>") {
              return buildDictionaryAutoGenBad(clipboard);
            }
            if (_clipboard.value == "&<&>netsubsrequest&<&>") {
              return buildDictionaryNetworkSubtitlesRequest(clipboard);
            }
            if (_clipboard.value == "&<&>netsubsbad&<&>") {
              return buildDictionaryNetworkSubtitlesBad(clipboard);
            }
            if (_clipboard.value.startsWith("&<&>exported")) {
              return buildDictionaryExported(clipboard);
            }
            if (_clipboard.value == "") {
              return Container();
            }

            switch (snapshot.connectionState) {
              case ConnectionState.waiting:
                return buildDictionaryLoading(clipboard);
              default:
                DictionaryHistoryEntry results = snapshot.data;

                if (snapshot.hasData && results.entries.isNotEmpty) {
                  return buildDictionaryMatch(results);
                } else {
                  return buildDictionaryNoMatch(clipboard);
                }
            }
          },
        );
      },
    );
  }
}

class MultipleTapGestureDetector extends InheritedWidget {
  final void Function() onTap;

  const MultipleTapGestureDetector({
    Key key,
    @required Widget child,
    @required this.onTap,
  }) : super(key: key, child: child);

  static MultipleTapGestureDetector of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<MultipleTapGestureDetector>();
  }

  @override
  bool updateShouldNotify(MultipleTapGestureDetector oldWidget) => false;
}
