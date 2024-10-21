import 'package:bruno/constants.dart';
import 'package:flutter/material.dart';

class DynamicChatList extends StatelessWidget {
  final List<ChatMessage> messages;
  final bool isLoading;

  DynamicChatList({required this.messages, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top:18,bottom: 0,left: 18,right: 18),
      child: ListView.builder(
        itemCount: messages.length + (isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < messages.length) {
            final message = messages[index];
            return Column(
              children: [
                SizedBox(height: 36),
                _buildPromptWidget(message.prompt),
                SizedBox(height: 9),
                _buildAnswerWidget(message.answer),
              ],
            );
          } else {
            return Center(child: CircularProgressIndicator());
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
            padding: EdgeInsets.symmetric(horizontal: 9, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: kLightPurple,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image(
                  image: AssetImage('images/User icon.png'),
                  height: 30,
                  width: 30,
                ),
                SizedBox(width: 18),
                Flexible(
                  child: Text(
                    prompt,
                    style: TextStyle(
                      color: kWhitePurple,
                      fontSize: 18,
                      fontFamily: 'MerriweatherSans',
                    ),
                  ),
                ),
                SizedBox(width: 9),
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
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kDarkPurple,
        borderRadius: BorderRadius.all(Radius.circular(30)),
      ),
      child: Text(
        answer,
        style: TextStyle(
          color: kLighterWhitePurple,
          fontSize: 18,
          fontWeight: FontWeight.w300,
          fontFamily: 'MerriweatherSans',
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