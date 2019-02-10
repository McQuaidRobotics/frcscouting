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
	key: 
	keytitle: 
	columns: 
	order: 
	filter: 
Ex. of variable:
  - 
    name: teamr1
    source: ##match##.red1
    type: string
inputs: 
output: