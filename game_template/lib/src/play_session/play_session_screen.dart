// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:game_template/src/cw/def.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart' hide Level;
import 'package:provider/provider.dart';

import '../ads/ads_controller.dart';
import '../audio/audio_controller.dart';
import '../audio/sounds.dart';
import '../game_internals/level_state.dart';
import '../games_services/games_services.dart';
import '../games_services/score.dart';
import '../in_app_purchase/in_app_purchase.dart';
import '../level_selection/levels.dart';
import '../player_progress/player_progress.dart';
import '../style/confetti.dart';
import '../style/palette.dart';

class PlaySessionScreen extends StatefulWidget {
  final GameLevel level;

  const PlaySessionScreen(this.level, {super.key});

  @override
  State<PlaySessionScreen> createState() => _PlaySessionScreenState();
}

class _PlaySessionScreenState extends State<PlaySessionScreen> {
  static final _log = Logger('PlaySessionScreen');

  static const _celebrationDuration = Duration(milliseconds: 2000);

  static const _preCelebrationDuration = Duration(milliseconds: 500);

  bool _duringCelebration = false;

  late DateTime _startOfPlay;

  bool firstLoading = true;
  late final String thisCW;
  late final int rows;
  late final int cols;
  bool isVertical = false;
  int lastTapped = -1;
  List<Definition> sol = [];
  List<Definition> def = [];
  Map<String, String> userInputs = Map();
  Map<String, List<int>> words = Map();
  List<TextEditingController> _controllers = [];
  final FocusScopeNode _node = FocusScopeNode();
  late String prevDir;
  late String prevPath;
  bool prevFileExists = false;
  Color normalCellColor = Colors.amber.shade50;
  Color highlightedCellColor = Colors.amber.shade100;
  Color highlightedCellColorDark = Colors.amber.shade300;
  Map<int, Color> cellsColors = Map(); // init in _loadStuff()
  String shownDef = '';
  dynamic  directory;
  dynamic  data3;
  dynamic  data;
  dynamic  data1;
  dynamic  data2;


  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) => LevelState(
            goal: widget.level.difficulty,
            onWin: _playerWon,
          ),
        ),
      ],
      child: IgnorePointer(
        ignoring: _duringCelebration,
        child: Scaffold(
          backgroundColor: palette.backgroundPlaySession,
          body: Stack(
            children: [
              Center(
                // This is the entirety of the "game".
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: InkResponse(
                        onTap: () => GoRouter.of(context).push('/settings'),
                        child: Image.asset(
                          'assets/images/settings.png',
                          semanticLabel: 'Settings',
                        ),
                      ),
                    ),
                    const Spacer(),
                    Column(
                      children: [
                        ButtonBar(
                          alignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton(
                              child: Text(
                                'Save',
                                style: TextStyle(fontSize: 20),
                              ),
                              onPressed: () {
                                _buttonPress("Save");
                              },
                            ),
                            ElevatedButton(
                              style: ButtonStyle(
                                  backgroundColor: MaterialStateColor.resolveWith(
                                          (states) => Colors.red)),
                              child: Text(
                                'Reset',
                                style: TextStyle(fontSize: 20),
                              ),
                              onPressed: () {
                                _buttonPress("Reset");
                              },
                            ),
                            ElevatedButton(
                              style: ButtonStyle(
                                  backgroundColor: MaterialStateColor.resolveWith(
                                          (states) => Colors.green)),
                              child: Text(
                                'Check',
                                style: TextStyle(fontSize: 20),
                              ),
                              onPressed: () {
                                _buttonPress("Check");
                              },
                            ),
                          ],
                        ),
                        // definition textbox
                        Container(
                          padding: EdgeInsets.only(left: 10, right: 10, bottom: 5, top: 0),
                          alignment: Alignment.centerLeft,
                          child: Text.rich(
                            TextSpan(
                              style: TextStyle(fontSize: 18),
                              children: <TextSpan>[
                                TextSpan(
                                    text: 'def: ',
                                    style: TextStyle(fontWeight: FontWeight.bold)),
                                TextSpan(
                                    text: shownDef,
                                    style: TextStyle(fontStyle: FontStyle.italic)),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          child: FutureBuilder(
                              future: TickerFuture.complete(),
                              builder: (context, snapshot) {
                                if (snapshot.hasData) {
                                  // sol = json.decode(snapshot.data.toString());
                                  return Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          left: 10, right: 10, top: 10, bottom: 10),
                                      child: GridView.count(
                                        // rows and cols are passed to this page as arguments from "home.dart", through routeGenerator
                                        crossAxisCount:
                                        cols, // n° elements in each row! a.k.a. "cols" property in "cwinfos.json"!
                                        children: List.generate(rows * cols, (index) {
                                          return FocusScope(
                                              node: _node,
                                              child: Container(
                                                width: 40,
                                                height: 40,
                                                decoration: BoxDecoration(
                                                    color: sol[index] == '-'
                                                        ? Color.fromRGBO(45, 91, 166, 1)
                                                        : Colors.white,
                                                    border: Border.all(color: Colors.black)),
                                                child: sol[index] == '-'
                                                    ? Text('')
                                                    : Container(
                                                  color: cellsColors[index],
                                                  child: TextField(
                                                    focusNode: FocusNode(),
                                                    // set the initial text to previously saved values
                                                    controller: _controllers[index]
                                                      ..text = (userInputs.containsKey(
                                                          index.toString())
                                                          ? userInputs[index.toString()]
                                                          : '')!,
                                                    textCapitalization:
                                                    TextCapitalization.sentences,
                                                    inputFormatters: [
                                                      LengthLimitingTextInputFormatter(
                                                          1),
                                                    ],
                                                    cursorWidth: 4,
                                                    cursorRadius: Radius.circular(2),
                                                    cursorHeight: 20,
                                                    enableInteractiveSelection: false,
                                                    textDirection: TextDirection.ltr,
                                                    textAlign: TextAlign.center,
                                                    decoration: InputDecoration(
                                                        contentPadding:
                                                        EdgeInsets.all(0),
                                                        focusedBorder:
                                                        OutlineInputBorder(
                                                            borderSide:
                                                            BorderSide.none),
                                                        enabledBorder:
                                                        OutlineInputBorder(
                                                            borderSide:
                                                            BorderSide.none)
                                                      // OutlineInputBorder(
                                                      //     borderRadius:
                                                      //         BorderRadius.all(
                                                      //             Radius.circular(0)),
                                                      //     borderSide: BorderSide(
                                                      //         color: Colors.grey[600])),
                                                    ),
                                                    cursorColor: Colors.black,
                                                    textAlignVertical:
                                                    TextAlignVertical.center,
                                                    style: TextStyle(
                                                        fontSize: 23,
                                                        fontWeight: FontWeight.bold,
                                                        decoration:
                                                        TextDecoration.none),
                                                    onTap: () {
                                                      // switches between vertical and horizontal directions
                                                      if (lastTapped == index) {
                                                        isVertical = !isVertical;
                                                      }
                                                      lastTapped = index;

                                                      // highlight word
                                                      _highlightWord(index);
                                                    },
                                                    onChanged: (text) {
                                                      lastTapped =
                                                      -1; // prevents it from flipping direction on previous tap, when auto-jumping to next cell
                                                      userInputs[index.toString()] =
                                                          text;
                                                      if (text.isEmpty) {
                                                        userInputs
                                                            .remove(index.toString());
                                                        _focusPrevious(index);
                                                      } else if (text.contains(
                                                          new RegExp(r'[A-Z]'))) {
                                                        // focus on next cell according to direction
                                                        _focusNext(index);
                                                      } else {
                                                        // cell contains not allowed characters
                                                        _controllers[index].text = "";
                                                      }
                                                    },
                                                  ),
                                                ),
                                              ));
                                        }),
                                      ),
                                    ),
                                  );
                                } else
                                  return Center(
                                    child: CircularProgressIndicator(),
                                  );
                              }),
                        )
                      ],
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => GoRouter.of(context).pop(),
                          child: const Text('Back'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox.expand(
                child: Visibility(
                  visible: _duringCelebration,
                  child: IgnorePointer(
                    child: Confetti(
                      isStopped: !_duringCelebration,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }



  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  void initState() {
    sol.clear();
    def.clear();
    super.initState();
    _loadDef();

    _startOfPlay = DateTime.now();

    // Preload ad for the win screen.
    final adsRemoved =
        context.read<InAppPurchaseController?>()?.adRemoval.active ?? false;
    if (!adsRemoved) {
      final adsController = context.read<AdsController?>();
      adsController?.preloadAd();
    }
  }

  Future<void> _playerWon() async {
    _log.info('Level ${widget.level.number} won');

    final score = Score(
      widget.level.number,
      widget.level.difficulty,
      DateTime.now().difference(_startOfPlay),
    );

    final playerProgress = context.read<PlayerProgress>();
    playerProgress.setLevelReached(widget.level.number);

    // Let the player see the game just after winning for a bit.
    await Future<void>.delayed(_preCelebrationDuration);
    if (!mounted) return;

    setState(() {
      _duringCelebration = true;
    });

    final audioController = context.read<AudioController>();
    audioController.playSfx(SfxType.congrats);

    final gamesServicesController = context.read<GamesServicesController?>();
    if (gamesServicesController != null) {
      // Award achievement.
      if (widget.level.awardsAchievement) {
        await gamesServicesController.awardAchievement(
          android: widget.level.achievementIdAndroid!,
          iOS: widget.level.achievementIdIOS!,
        );
      }

      // Send score to leaderboard.
      await gamesServicesController.submitLeaderboardScore(score);
    }

    /// Give the player some time to see the celebration animation.
    await Future<void>.delayed(_celebrationDuration);
    if (!mounted) return;

    GoRouter.of(context).go('/play/won', extra: {'score': score});
  }

  void _focusNext(int index) {
    // code for preventing auto-jumps over blue cells
    isVertical == false
        ? {
      if (sol[(index + 1) % (rows * cols)] != '-')
        _node.focusInDirection(TraversalDirection.right)
    }
        : {
      if (sol[(index + cols) % (rows * cols)] != '-')
        _node.focusInDirection(TraversalDirection.down)
    };
  }

  void _buttonPress(String button) {
    switch (button) {
      case "Reset":
        _askForReset();
        break;
      case "Save":
        _saveInputs();
        break;
      // case "Check":
      //   checkInputs();
      //   break;
    }
  }

  // void checkInputs() {
  //   String msg = '';
  //   String title = '';
  //   int wrong = 0;
  //   int missing = 0;
  //   for (int i = 0; i < sol.length; i++) {
  //     String el = sol[i].toUpperCase();
  //     if (el != '-') {
  //       if (userInputs.containsKey(i.toString())) {
  //         if (userInputs[i.toString()] != el) {
  //           wrong++;
  //           missing++;
  //           _controllers[i].text = '_';
  //         }
  //       } else
  //         missing++;
  //     }
  //   }
  //   if (missing == 0) {
  //     // winning condition
  //     title = 'Done!';
  //     msg = "Congratulations.\nThere are no errors!";
  //   } else {
  //     title = 'Stats:';
  //     msg = "Wrong: ${wrong}\nRemaining: ${missing}";
  //   }
  //   // notify user about statistics
  //   AlertDialog(
  //     title: Text(title, style: TextStyle(fontSize: 25)),
  //     content: Text(msg, style: TextStyle(fontSize: 18)),
  //     actions: [
  //       ElevatedButton(
  //           onPressed: () {
  //             if (missing == 0) {
  //               ScaffoldMessenger.of(context).showSnackBar(
  //                 SnackBar(
  //                   content: Text('CW #$thisCW has been completed!',
  //                       style: TextStyle(fontSize: 15)),
  //                 ),
  //               );
  //             }
  //             HapticFeedback.vibrate();
  //             Navigator.of(context).pop();
  //           },
  //           child: Text('Ok', style: TextStyle(fontSize: 18))),
  //     ],
  //   );
  // }

  void _saveInputs() {
    // only saves status if there are letters on the board
    if (userInputs.isNotEmpty) {
      final writeData = json.encode(userInputs);
      File(prevPath).createSync(recursive: true);
      File prevFile = new File(prevPath);
      prevFile.writeAsString(writeData.toString()).then((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CW #$thisCW has been saved...',
                style: TextStyle(fontSize: 15)),
          ),
        );
        HapticFeedback.vibrate();
      });
    }
    // if there's no letter AND the file exists, remove it to save its status as empty
    else if (prevFileExists) {
      File(prevPath).delete().then((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CW #$thisCW has been saved...',
                style: TextStyle(fontSize: 15)),
          ),
        );
        HapticFeedback.vibrate();
      });
    }
    // here the file has never been created and the user wants to save an empty status, thus do nothing
    else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('CW #$thisCW has never been saved before...',
              style: TextStyle(fontSize: 15)),
        ),
      );
      HapticFeedback.vibrate();
    }
  }

// shows an alert dialog asking for Reset confirmation
  void _askForReset() {
    AlertDialog(
      title: Text("Reset!", style: TextStyle(fontSize: 25)),
      content: Text("Are you sure? Any unsaved changes will be lost.",
          style: TextStyle(fontSize: 18)),
      actions: [
        ElevatedButton(
            style: ButtonStyle(
                backgroundColor:
                MaterialStateColor.resolveWith((states) => Colors.white)),
            onPressed: () {
              HapticFeedback.vibrate();
              Navigator.of(context).pop();
            },
            child:
            Text('No', style: TextStyle(fontSize: 18, color: Colors.blue))),
        ElevatedButton(
            onPressed: () {
              setState(() {
                _controllers.forEach((ctrl) {
                  ctrl.text = '';
                });
              });

              setState(() {
                userInputs.clear();
              });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('CW #$thisCW has been reset...',
                      style: TextStyle(fontSize: 15)),
                ),
              );
              HapticFeedback.vibrate();
              Navigator.of(context).pop();
            },
            child: Text('Yes', style: TextStyle(fontSize: 18))),
      ],
    );
  }



  void _highlightWord(int index) {
    // get right definition/word (vertical or horizontal ones)
    Definition d = def[index];
    String defStr = isVertical ? d.vDef : d.hDef;
    String word = isVertical ? d.vWord : d.hWord;

    if (word != '-') {
      setState(() {
        _resetCellsColors();
        // definition setting
        shownDef = defStr;
        // highlight only word's cells
        words[word]?.asMap().forEach((index, el) {
          if (index == 0) {
            cellsColors.update(el, (value) => highlightedCellColorDark);
            return;
          }
          cellsColors.update(el, (value) => highlightedCellColor);
        });
      });
    }
  }

  void _resetCellsColors() {
    cellsColors.forEach((key, value) {
      if (value == highlightedCellColor || value == highlightedCellColorDark)
        cellsColors.update(key, (value) => normalCellColor);
    });
  }

  void _getCurrentStuff() {
    // prevents 'setState' to read again from disk
    return;
  }

  void _focusPrevious(int index) {
    // code for preventing auto-jumps over blue cells
    isVertical == false
        ? {
      if (sol[(index - 1) % (rows * cols)] != '-')
        _node.focusInDirection(TraversalDirection.left)
    }
        : {
      if (sol[(index + cols) % (rows * cols)] != '-')
        _node.focusInDirection(TraversalDirection.up)
    };
  }
}
