---
type: enum: [question, input, list, report]
id: a unique string, reference id on other pages. Suggestion: id = pagename
key: a string specifying the grouping of questions - Generates a question for each member of the data entry specified. Optional, can have multiple separated by periods. 
role: a string specifying the role that the question will show up to. If a user has a role set they will only get questions from that role.
priority: A numerical priority for questions. Lower number is a higher priority. 
dataneeded: A number saying how many times this question needs to be answered. If higher than 1, each time the question is asked it will be to a different person.
expvalue: A number saying how much experience a user gets for answering this question.
reqlevel: A number specifying the level a user must be in order to see the content
title: A string title for the back
populate: For lists only, a list of data. Ex.
  - Switch
  - Scale
  - Vault
  - Defense
  - Endgame
variables: A list of variables referenced in the file that are not already declared in the key. Referred to later as ##name##
  - 
    name: String name of the variable. Referenced as ##name##
    source: The source of the variable, in the form of key.id.
    type: enum: [string, average, table, commentlist, stringcount, count, sum, sql]
	  - String: the newest value from the source
	  - Average: A number that is the average of values reported from all matches
	  - Table: A set of other variables. The source for a table sets where the data is gathered from. Additional variables can be declared in a table to report variables from the source.
	  - Commentlist: A list of strings from the string table formatted into a bullet list
	  - Stringcount: The number of entries in the string table
	  - Count: The number of entries in the number table that match the filter, if provided
	  - Sum: Add together entries in the number table that match the source and filter
	  - Sql: 
	key: The group to take the data from
	keytitle: A string title for the key group - used as a table header
	columns: Columns for a table - a set of variables where each variable is another column on the table
	order: Put into sql to order a table output
	filter: put into sql to filter a table output
Ex. of variable:
  - 
    name: teamr1
    source: ##match##.red1
    type: string
inputs: A list of interactable elements on a page. Inputs can have the following:
  -
    type: enum: [label, tally, submit, text, button, list, number]
	  - label: Prints label to the screen
	  - tally: A numerical input that you use + and - to increment
	  - submit: A button that can have actions done upon being interacted with
	  - text: An input that accepts a string
	  - button: A button that can have actions done on being interacted with
	  - list: Select a value from a list
	  - number: An input that accepts a number
	listdata: The list from which you select a value from
	label: A string that will be shown as the label. Can include <br>
	style: CSS styling to be put on the input
	do: A series of commands that will be executed upon the input being interacted with
	saveas: the name to save the value as. Can be referenced later in variables
output: HTML output to the screen. Reference variables by using ##variable##. 
  Ex:
output: >-
  Team ##team##<br>
  ##teamname##<br>
  Average Cargo - ##cargoavg##<br>
  ##comments##