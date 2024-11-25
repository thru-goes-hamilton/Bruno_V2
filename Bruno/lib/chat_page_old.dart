import 'dart:convert';
import 'dart:math';
import 'package:bruno/chat_components.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/file_icons.dart';
import 'package:iconify_flutter/icons/carbon.dart';
import 'package:iconify_flutter/icons/ic.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:html' as html;
import 'constants.dart';

class ChatHandler {
  List<ChatMessage> messages = [];
  bool isLoading = false;
  final String sessionId; // Add this to store the session ID

  ChatHandler({required this.sessionId});

  Future<void> sendQuery(
      String prompt, Function setState, BuildContext context) async {
    print("entered second send query, prompt:$prompt");
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a prompt')),
      );
      return;
    }

    setState(() {
      isLoading = true;
      messages.add(ChatMessage(prompt: prompt, answer: ''));
    });

    try {
      // Prepare the chat history in the required format
      final chatHistory = messages
          .map((msg) => {
                'role': 'user',
                'content': msg.prompt,
              })
          .toList();

      // If there are answers, add them to chat history
      for (var i = 0; i < messages.length - 1; i++) {
        if (messages[i].answer.isNotEmpty) {
          chatHistory.insert(2 * i + 1, {
            'role': 'assistant',
            'content': messages[i].answer,
          });
        }
      }

      // Prepare the request body
      final requestBody = {
        'message': prompt,
        'chat_history': [],
        'use_rag': true // You can make this configurable if needed
      };
      print("ready to send result");
      // Create the request
      final request = http.Request(
        'POST',
        Uri.parse('https://bruno-v2.onrender.com/query/$sessionId'),
      );

      request.headers['Content-Type'] = 'application/json';
      request.body = json.encode(requestBody);

      // Send the request and get the stream
      final response = await http.Client().send(request);

      // Handle the server-sent events
      response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((String line) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6); // Remove 'data: ' prefix
          try {
            final jsonData = json.decode(data);
            final content = jsonData['content'];

            if (content == '[DONE]') {
              setState(() {
                isLoading = false;
              });
            } else {
              setState(() {
                // Update the last message's answer with the new content
                messages[messages.length - 1].answer += content;
                print(messages[messages.length -1].answer);
              });
            }
          } catch (e) {
            print('Error parsing SSE data: $e');
          }
        }
      }, onError: (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $error')),
        );
        setState(() {
          isLoading = false;
        });
      }, cancelOnError: true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending query: $e')),
      );
      setState(() {
        isLoading = false;
      });
    }
  }
}

class Bruno extends StatefulWidget {
  const Bruno({super.key});

  @override
  State<Bruno> createState() => _BrunoState();
}

class _BrunoState extends State<Bruno> with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  late final ChatHandler chatHandler;
  bool isUploading = false;
  bool isExtracting = false;
  bool isDeleting = false;
  bool isSending = false;
  String? fileName;
  String? fileType;
  String? cacheFileName;
  String? temp_prompt;

  List<ChatMessage> get messages => chatHandler.messages;
  bool get isLoading => chatHandler.isLoading;
  String get sessionId => chatHandler.sessionId;

  late AnimationController _animationcontroller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  String generateSessionId() {
    final random = Random();
    const letters = 'abcdefghijklmnopqrstuvwxyz';

    // Generate 3 random lowercase letters
    String randomLetters =
        List.generate(3, (_) => letters[random.nextInt(letters.length)]).join();

    // Generate 3 random numbers
    String randomNumbers =
        List.generate(3, (_) => random.nextInt(10).toString()).join();

    // Combine them
    return randomLetters + randomNumbers;
  }

  Future<void> uploadFile(BuildContext context) async {
    setState(() {
      isUploading = true;
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt'],
      );

      if (result != null) {
        var file = result.files.single;
        fileName = file.name;
        fileType = file.extension;

        var request = http.MultipartRequest(
          'POST',
          Uri.parse(
              'https://bruno-v2.onrender.com/upload/${chatHandler.sessionId}'), // Include session_id in the URL
        );

        request.files.add(
          http.MultipartFile.fromBytes('file', file.bytes!,
              filename: file.name),
        );

        var response = await request.send();

        if (response.statusCode == 200) {
          print("Atmepting to extract");
          await extractAndVectorize(context);

          ScaffoldMessenger.of(context as BuildContext).showSnackBar(
            SnackBar(content: Text('File uploaded successfully')),
          );
        } else {
          throw Exception('Failed to upload file');
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('Error uploading file: $e')),
      );
    } finally {
      setState(() {
        isUploading = false;
      });
    }
  }

  Future<void> deleteFile(String fileName) async {
    setState(() {
      isDeleting = true;
    });

    try {
      final response = await http.delete(
        Uri.parse(
            'https://bruno-v2.onrender.com/delete/${chatHandler.sessionId}/$fileName'),
      );

      if (response.statusCode == 200) {
        truncateDatabase(chatHandler.sessionId);
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          SnackBar(content: Text('File deleted successfully')),
        );
      } else {
        throw Exception('Failed to delete file');
      }
    } catch (e) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('Error deleting file: $e')),
      );
    } finally {
      setState(() {
        isDeleting = false;
      });
    }
  }

  Future<void> extractAndVectorize(BuildContext context) async {
    setState(() {
      isExtracting = true;
    });
    print("inside extract");
    try {
      var response = await http.post(
        Uri.parse(
            'https://bruno-v2.onrender.com/extract-and-vectorize/${chatHandler.sessionId}'),
      );

      if (response.statusCode == 200) {
        var jsonResponse = jsonDecode(response.body);
        // ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        //   SnackBar(content: Text(jsonResponse['message'])),
        // );
        print(jsonResponse['message']);
      } else {
        throw Exception('Failed to extract and vectorize');
      }
    } catch (e) {
      deleteAllFiles();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e. The file has exceeded size limit.')),
      );
    } finally {
      setState(() {
        isExtracting = false;
      });
    }
  }

  void truncateDatabaseWithBeacon(String sessionId) {
    // Define the endpoint URL
    String url = 'https://bruno-v2.onrender.com/truncate/$sessionId';

    // Send a beacon request to the server to truncate the database
    html.window.navigator.sendBeacon(url, null);
  }

  void deleteAllFilesWithBeacon(String sessionId) {
    // Define the endpoint URL with the sessionId
    final url = 'https://bruno-v2.onrender.com/delete-session/$sessionId';

    // Send a beacon request to delete all files for the given session
    html.window.navigator.sendBeacon(url, null);
  }

  void clearStateWithBeacon(String sessionId) {
    // Define the endpoint URL with the sessionId
    final url = 'https://bruno-v2.onrender.com/cleanup/$sessionId';

    // Send a beacon request to delete all files for the given session
    html.window.navigator.sendBeacon(url, null);
  }

  Future<void> truncateDatabase(String sessionId) async {
    try {
      // Send the HTTP POST request to the truncate endpoint
      final response = await http.post(
        Uri.parse('https://bruno-v2.onrender.com/truncate/$sessionId'),
      );

      // Check if the response indicates success
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          SnackBar(content: Text('Database truncated successfully')),
        );
      } else {
        throw Exception('Failed to truncate database');
      }
    } catch (e) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('Error truncating database: $e')),
      );
    }
  }

  Future<void> deleteAllFiles() async {
    try {
      // Send the HTTP DELETE request to the delete-all endpoint
      final response = await http.delete(
        Uri.parse(
            'https://bruno-v2.onrender.com/delete-session/${chatHandler.sessionId}'),
      );

      // Check if the response indicates success
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          SnackBar(content: Text('All files deleted successfully')),
        );
      } else {
        throw Exception('Failed to delete all files');
      }
    } catch (e) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('Error deleting files: $e')),
      );
    }
  }

  Future<void> sendQuery(BuildContext context, String prompt) async {
    await chatHandler.sendQuery(
      prompt,
      setState,
      context,
    );
  }

  void _handleSubmit(BuildContext context) async {
    if (isUploading | isExtracting) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Press the send button after the file is finished processing",
            style: TextStyle(color: kWhitePurple),
          ),
          backgroundColor: kLightPurple,
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (isSending) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Wait for the result from current prompt",
            style: TextStyle(color: kWhitePurple),
          ),
          backgroundColor: kLightPurple,
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      isSending = true;
      temp_prompt = _controller.text.trim();
      _controller.clear();
      await sendQuery(context, temp_prompt!);
      isSending = false;
    }
  }

  @override
  void initState() {
    super.initState();
    chatHandler = ChatHandler(sessionId: generateSessionId());
    print('Generated Session ID: $chatHandler.sessionId');
    html.window.onBeforeUnload.listen((event) {
      if (event is html.BeforeUnloadEvent) {
        truncateDatabaseWithBeacon(chatHandler.sessionId);
        deleteAllFilesWithBeacon(chatHandler.sessionId);
        clearStateWithBeacon(chatHandler.sessionId);
        print("about to exit");
        event.returnValue = 'Some return value here';
      }
    });

    // Initialize AnimationController
    _animationcontroller = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );

    // Define slide-in animation from left
    _slideAnimation = Tween<Offset>(
      begin: Offset(-1.0, 0.0), // Start slightly off-screen to the left
      end: Offset.zero, // End at its original position
    ).animate(
      CurvedAnimation(
        parent: _animationcontroller,
        curve: Curves.easeOut,
      ),
    );

    // Define fade-in animation
    _fadeAnimation = Tween<double>(
      begin: 0.0, // Fully transparent
      end: 1.0, // Fully visible
    ).animate(
      CurvedAnimation(
        parent: _animationcontroller,
        curve: Curves.easeOut,
      ),
    );

    // Start the animation after a delay (to wait for Hero animation)
    Future.delayed(Duration(milliseconds: 500), () {
      _animationcontroller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SelectionArea(
        child: Container(
          height: MediaQuery.of(context).size.height,
          width: MediaQuery.of(context).size.width,
          color: kDarkPurple,
          padding: EdgeInsets.only(top: 18, left: 27, right: 27, bottom: 18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Hero(
                    tag: 'brainIcon',
                    child: Iconify(FileIcons.brainfuck,
                        size: 30, color: kLighterWhitePurple),
                  ),
                  SizedBox(width: 20),
                  Hero(
                    tag: 'brunoText',
                    child: Text(
                      'BRUNO',
                      style: TextStyle(
                        color: kLighterWhitePurple,
                        fontSize: 26,
                        fontFamily: 'Merriweather',
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 18),
              Expanded(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 200, vertical: 9),
                          child: Column(
                            children: [
                              Expanded(
                                child: DynamicChatList(
                                  messages: chatHandler.messages,
                                  isLoading: isLoading,
                                ),
                              ),
                              fileName != null
                                  ? Row(
                                      children: [
                                        SizedBox(
                                          width: 18,
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 4.5),
                                          child: Chip(
                                            backgroundColor: kLightPurple,
                                            deleteIcon: Icon(
                                              Icons.close,
                                              size: 18,
                                              color: kLighterWhitePurple,
                                            ),
                                            onDeleted: () {
                                              deleteFile(fileName!);
                                              setState(() {
                                                fileName = null;
                                              });
                                            },
                                            avatar: Icon(
                                              Icons.insert_drive_file,
                                              size: 18,
                                              color: kLighterWhitePurple,
                                            ),
                                            label: Text(
                                              fileName!.length > 8
                                                  ? fileName!.substring(0, 8) +
                                                      '...'
                                                  : fileName!,
                                              style: TextStyle(
                                                  fontSize: 16,
                                                  fontFamily:
                                                      "MerriweatherSans",
                                                  color: kLighterWhitePurple),
                                            ),
                                          ),
                                        ),
                                        Expanded(child: SizedBox()),
                                      ],
                                    )
                                  : SizedBox(height: 0),
                              Stack(
                                children: [
                                  Container(
                                    constraints: BoxConstraints(
                                      maxHeight:
                                          150, // Set a maximum height for the text field
                                    ),
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 25),
                                    decoration: BoxDecoration(
                                      color: kWhitePurple,
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: TextField(
                                      cursorColor: kDarkPurple,
                                      controller: _controller,
                                      maxLines: null, // Allow multiple lines
                                      keyboardType: TextInputType
                                          .multiline, // Enable multiline input
                                      textInputAction: TextInputAction
                                          .newline, // Use newline action for enter key
                                      decoration: InputDecoration(
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 9, vertical: 15),
                                        hintText: "Talk to Bruno...",
                                        hintStyle: TextStyle(
                                          color: kDarkPurple,
                                          fontSize: 18,
                                          fontFamily: 'MerriweatherSans',
                                        ),
                                        border: InputBorder.none,
                                      ),
                                      style: TextStyle(
                                        color: kDarkPurple,
                                        fontSize: 18,
                                        fontFamily: 'MerriweatherSans',
                                      ),
                                      onSubmitted: (_) => _handleSubmit(
                                          context), // Fallback if action is 'done'
                                      onEditingComplete: () => _handleSubmit(
                                          context), // Handles pressing Enter
                                      focusNode: FocusNode(
                                        onKey: (FocusNode node,
                                            RawKeyEvent event) {
                                          if (event.isKeyPressed(
                                                  LogicalKeyboardKey.enter) &&
                                              !event.isShiftPressed) {
                                            // Prevent newline when Enter is pressed without Shift
                                            _handleSubmit(context);
                                            return KeyEventResult.handled;
                                          }
                                          return KeyEventResult.ignored;
                                        },
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    bottom: 0,
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: kLightPurple,
                                            borderRadius:
                                                BorderRadius.circular(30),
                                          ),
                                          child: IconButton(
                                            icon: isUploading
                                                ? SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                                  Color>(
                                                              kWhitePurple),
                                                    ),
                                                  )
                                                : Iconify(Ic.round_attach_file,
                                                    size: 20,
                                                    color: kWhitePurple),
                                            onPressed: () async {
                                              if (!isUploading) {
                                                // Call uploadFile and another function here
                                                await uploadFile(context);
                                              }
                                              // await extractAndVectorize();
                                            },
                                            padding: EdgeInsets.zero,
                                          ),
                                        ),
                                        SizedBox(width: 4.5),
                                        Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: kDarkPurple,
                                            borderRadius:
                                                BorderRadius.circular(30),
                                          ),
                                          child: IconButton(
                                            icon: Iconify(Carbon.send_filled,
                                                size: 20,
                                                color:
                                                    isUploading | isExtracting
                                                        ? kLightPurple
                                                        : kWhitePurple),
                                            onPressed: () async {
                                              if (isUploading | isExtracting) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      "Press the send button after the file is finished processing",
                                                      style: TextStyle(
                                                          color:
                                                              kWhitePurple), // Snackbar text color
                                                    ),
                                                    backgroundColor:
                                                        kLightPurple,
                                                    // Snackbar background color
                                                    duration: Duration(
                                                        seconds:
                                                            2), // Duration for how long the Snackbar will be visible
                                                    behavior: SnackBarBehavior
                                                        .floating, // Floating Snackbar
                                                  ),
                                                );
                                              } else if (isSending) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      "Wait for the result from current prompt",
                                                      style: TextStyle(
                                                          color:
                                                              kWhitePurple), // Snackbar text color
                                                    ),
                                                    backgroundColor:
                                                        kLightPurple,
                                                    // Snackbar background color
                                                    duration: Duration(
                                                        seconds:
                                                            2), // Duration for how long the Snackbar will be visible
                                                    behavior: SnackBarBehavior
                                                        .floating, // Floating Snackbar
                                                  ),
                                                );
                                              } else {
                                                isSending = true;
                                                temp_prompt =
                                                    _controller.text.trim();
                                                _controller.clear();
                                                await sendQuery(
                                                    context, temp_prompt!);
                                                isSending = false;
                                              }
                                            },
                                          ),
                                        ),
                                        SizedBox(width: 4.5),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
