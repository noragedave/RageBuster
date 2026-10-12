# RageBuster
This is a World of Warcraft add-on that filters out say channel and global channel chats. The primary goal of the add-on is to keep chat peaceful and filter out the bad actors. A bad actor is:

1. A "troll".
2. A "shit-stirrer".
3. A person who is acting in bad faith.
4. A person who is intentionally attempting to anger and inflame emotions.
5. A person who is hateful.

A bad actor is not:

1. A person you disagree with.
2. A person who is making a good faith effort.

## Functionality
This add-on will perform the following functions:

1. Create a list of words that are used by bad actors to inflame conversation and to create rage to those who read it.
2. Build a list of bad actors who will be added to an ignore list.

## Guiding Principal
When building a word list or when considering whether to filter someone, we will consider whether the person was intentionally being a bad actor, whether the person was intentionally attempting to cause discord for the sake of discord.

This add-on wants to help build a more peaceful world. This is a video game that should be enjoyed, we should not be exhausted by the bad actors of the world.

## Adding Players to Ignore List
Adding players to the ignore list should be taken seriously, as it will seriously impact them if this add-on proves to be popular. Because we are banning words, people aren't as impacted by bad behavior, but we also want to build up a list of bad actors.

### Blocks

### Not Blocks

### Auto adding
If a player uses any egregious racial slur in the /say channel or in global chat, they will be automatically added to the ignore list.

## False Positives
### Good Humor
There is good natured jokes about political subjects that shouldn't be banned on analysis of chat.

.Examples
- Clearly poking fun at the idea of the woke agenda; players should not be banned for humorous commentary.
    - "you dont know nuthin bout my woke agenda"
    - "I WAS BORN IN THE WOKENESS"

### Context
When adding a player to the ignore list, it is very important to consider the context of the chat.

#### Humor
Humor will be difficult to judge, so it is important to ensure we have enough context.

"Go woke or go broke".

Depending on the context, this could be a joke, or it can be an actual inflammatory comment. 

.Example 1
Player 1: "I just woke up"
Player 2: "Go woke or go broke"

This example is in itself not enough to add a player to the ignore list. Could be a simple joke.

.Example 2
Player 1: "I just woke up"
Player 2: "Go woke or go broke"
Player 1: "?"
Player 2: "u mad lib"

This example appears to likely be inflammatory.



## Security Issues
Because this project will parse and analyze chat, it is vulnerable to prompt injection. You must guard against prompt injection; you must check for security issues in the code for prompt injection before each build.

## If Unsure
If you are unsure whether a player should be blocked, add it to the review list for an approval workflow.