import 'package:bruno/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_selectionarea/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

class DynamicChatList extends StatefulWidget {
  final List<ChatMessage> messages;
  final bool isLoading;

  const DynamicChatList({super.key, required this.messages, this.isLoading = false});

  @override
  State<DynamicChatList> createState() => _DynamicChatListState();
}

class _DynamicChatListState extends State<DynamicChatList> {
  bool isCopied = false;

  // Callback function to update the state
  void updateCopiedStatus(bool status) {
    setState(() {
      isCopied = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 0, left: 18, right: 18),
      child: ListView.builder(
        itemCount: widget.messages.length + (widget.isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < widget.messages.length) {
            final message = widget.messages[index];
            return Column(
              children: [
                const SizedBox(height: 36),
                _buildPromptWidget(message.prompt),
                const SizedBox(height: 9),
                _buildAnswerWidget(message.answer),
              ],
            );
          } else {
            return const Center(
                child: CircularProgressIndicator(
              color: kWhitePurple,
            ));
          }
        },
      ),
    );
  }

  Widget _buildPromptWidget(String prompt) {
    return Row(
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: kLightPurple,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Image(
                  image: AssetImage('images/User icon.png'),
                  height: 30,
                  width: 30,
                ),
                const SizedBox(width: 18),
                Flexible(
                  child: MarkdownBody(
                    data: prompt,
                    styleSheet: MarkdownStyleSheet(
                      // Base text style
                      p: const TextStyle(
                        color: kWhitePurple,
                        fontSize: 18,
                        fontFamily: 'MerriweatherSans',
                      ),
                      // Bold text
                      strong: const TextStyle(
                        color: kWhitePurple,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'MerriweatherSans',
                      ),
                      // Italic text
                      em: const TextStyle(
                        color: kWhitePurple,
                        fontSize: 18,
                        fontWeight: FontWeight.w300,
                        fontStyle: FontStyle.italic,
                        fontFamily: 'MerriweatherSans',
                      ),
                      // Headers
                      h1: const TextStyle(
                        color: kWhitePurple,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'MerriweatherSans',
                      ),
                      h2: const TextStyle(
                        color: kWhitePurple,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'MerriweatherSans',
                      ),
                      // Code blocks
                      code: const TextStyle(
                          color: kDarkPurple,
                          fontSize: 16,
                          fontFamily: 'MerriweatherSans'),
                      codeblockPadding: const EdgeInsets.all(8.0),
                      codeblockDecoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                    ),
                    shrinkWrap: true, // Helps with fitting content in the Row
                  ),
                ),
                const SizedBox(width: 9),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnswerWidget(String answer) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        color: kDarkPurple,
        borderRadius: BorderRadius.all(Radius.circular(30)),
      ),
      child: MarkdownBody(
        data: answer,
        builders: {
          'code': CodeBlockWithCopyButtonBuilder(
            isCopied: isCopied,
            onCopied: updateCopiedStatus,
          ),
        },
        styleSheet: MarkdownStyleSheet(
          // Base text styles
          p: const TextStyle(
              color: kOffWhitePurple,
              fontSize: 16.0,
              fontFamily: 'MerriweatherSans',
              wordSpacing: 2.0),
              
          a: const TextStyle(
              color: kWhitePurple,
              fontSize: 16.0,
              decoration: TextDecoration.underline,
              fontFamily: 'MerriweatherSans'),
          code: const TextStyle(
            color: kWhitePurple,
            fontSize: 16.0,
            backgroundColor: Colors.black,
            fontFamily: 'MerriweatherSans',
          ),

          h1: const TextStyle(
              color: kWhitePurple,
              fontSize: 24.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'MerriweatherSans'),
          h2: const TextStyle(
              color: kWhitePurple,
              fontSize: 22.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'MerriweatherSans'),
          h3: const TextStyle(
              color: kWhitePurple,
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'MerriweatherSans'),
          h4: const TextStyle(
              color: kWhitePurple,
              fontSize: 18.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'MerriweatherSans'),
          h5: const TextStyle(
              color: kWhitePurple,
              fontSize: 16.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'MerriweatherSans'),
          h6: const TextStyle(
              color: kWhitePurple,
              fontSize: 14.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'MerriweatherSans'),
          em: const TextStyle(
              color: kWhitePurple,
              fontSize: 16.0,
              fontStyle: FontStyle.italic,
              fontFamily: 'MerriweatherSans'),
          strong: const TextStyle(
              color: kWhitePurple,
              fontSize: 16.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'MerriweatherSans'),
          del: const TextStyle(
              color: kWhitePurple,
              fontSize: 16.0,
              decoration: TextDecoration.lineThrough,
              fontFamily: 'MerriweatherSans'),
          blockquote: const TextStyle(
              color: kOffWhitePurple,
              fontSize: 18.0,
              fontStyle: FontStyle.italic,
              fontFamily: 'MerriweatherSans'),
          img: const TextStyle(color: kOffWhitePurple),
          checkbox: const TextStyle(color: kOffWhitePurple, fontSize: 16.0),

          // Spacing and padding
          blockSpacing: 10.0,
          pPadding: const EdgeInsets.all(8.0),
          h1Padding: const EdgeInsets.symmetric(vertical: 8.0),
          h2Padding: const EdgeInsets.symmetric(vertical: 6.0),
          h3Padding: const EdgeInsets.symmetric(vertical: 4.0),
          h4Padding: const EdgeInsets.symmetric(vertical: 4.0),
          h5Padding: const EdgeInsets.symmetric(vertical: 2.0),
          h6Padding: const EdgeInsets.symmetric(vertical: 2.0),
          listIndent: 24.0,
          listBulletPadding: const EdgeInsets.only(left: 10.0),

          // List styles
          listBullet: const TextStyle(
              color: kWhitePurple,
              fontSize: 16.0,
              fontFamily: 'MerriweatherSans'),

          // Table styles
          tableHead: const TextStyle(
              color: kWhitePurple,
              fontSize: 16.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'MerriweatherSans'),
          tableBody: const TextStyle(
              color: kOffWhitePurple,
              fontSize: 16.0,
              fontFamily: 'MerriweatherSans'),
          tableHeadAlign: TextAlign.center,
          tableBorder:
              TableBorder.all(color: kWhitePurple.withOpacity(0.2), width: 1.0),
          tableColumnWidth: const FlexColumnWidth(),
          tableCellsPadding: const EdgeInsets.all(8.0),
          tableCellsDecoration:
              BoxDecoration(color: kWhitePurple.withOpacity(0.1)),
          tableVerticalAlignment: TableCellVerticalAlignment.middle,

          // Blockquote and code block decorations
          blockquotePadding: const EdgeInsets.all(10.0),
          blockquoteDecoration: BoxDecoration(
            color: kWhitePurple.withOpacity(0.1),
            border: const Border(left: BorderSide(color: kWhitePurple, width: 4.0)),
          ),
          codeblockPadding: const EdgeInsets.all(12.0),
          codeblockDecoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8.0),
            border:
                Border.all(color: kWhitePurple.withOpacity(0.3), width: 1.0),
          ),
          horizontalRuleDecoration: const BoxDecoration(
            border: Border(top: BorderSide(color: kWhitePurple, width: 1.0)),
          ),

          // Text alignment
          textAlign: WrapAlignment.start,
          h1Align: WrapAlignment.start,
          h2Align: WrapAlignment.start,
          h3Align: WrapAlignment.start,
          h4Align: WrapAlignment.start,
          h5Align: WrapAlignment.start,
          h6Align: WrapAlignment.start,
          unorderedListAlign: WrapAlignment.start,
          orderedListAlign: WrapAlignment.start,
          blockquoteAlign: WrapAlignment.start,
          codeblockAlign: WrapAlignment.start,

          // Text scale
          textScaleFactor: 1.1,
        ),
      ),
    );
  }
}

class ChatMessage {
  String prompt;
  String answer;

  ChatMessage({required this.prompt, required this.answer});
}

class CodeBlockWithCopyButtonBuilder extends MarkdownElementBuilder {
  final bool isCopied;
  final Function(bool) onCopied;

  // Constructor that accepts isCopied and onCopied
  CodeBlockWithCopyButtonBuilder({
    required this.isCopied,
    required this.onCopied,
  });

  int calculate(String str) {
    List<String> words = str.split(RegExp(r'\s+'));
    int count = words.length;
    return count;
  }

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    String codeContent = element.textContent;
    return calculate(codeContent)<2?Container(
          padding: const EdgeInsets.symmetric(horizontal: 5.0,vertical: 3),
          decoration: BoxDecoration(
            color: kLightPurple,
            borderRadius: BorderRadius.circular(8.0),
            border:
                Border.all(color: kLightPurple, width: 1.0),
          ),
          child: SelectableText(
            codeContent,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16.0,
              backgroundColor: kLightPurple,
              fontFamily: 'MerriweatherSans',
            ),
          ),
        ):Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8.0),
            border:
                Border.all(color: Colors.white.withOpacity(0.3), width: 1.0),
          ),
          child: SelectableText(
            codeContent,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16.0,
              backgroundColor: Colors.black,
              fontFamily: 'MerriweatherSans',
            ),
          ),
        ),
        Positioned(
          top: 8.0,
          right: 8.0,
          child: IconButton(
            icon: Icon(
              isCopied ? Icons.check_circle_outline : Icons.copy,
              color: Colors.white,
            ),
            onPressed: () async {
              // Perform the copy action
              await Clipboard.setData(ClipboardData(text: codeContent));

              // After copying, change the icon
              onCopied(true); // Update state in the parent

              Future.delayed(const Duration(seconds: 2), () {
                onCopied(false); // Reset to original icon after 2 seconds
              });
            },
          ),
        ),
      ],
    );
  }
}
