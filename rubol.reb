Rebol [
    Title: "Rubol"
    Purpose: "Extensions to Rebol to make it more Ruby-like"
    Description: {
    	This was a thought experiment about how to ease a 
		developer who is familiar with Ruby into learning Rebol, and
		perhaps to help focus discussion on the essential differences
		between the languages.

		It employs some unusual hackery.  While such hackery is not a 
		great idea to use in practice, it helps in two ways:

			#1 - It shows Rebol doing some interesting-yet-cheap 
			acrobatics to let you redefine the language (in ways you
			simply could not do with other systems)

			#2 - It gives a boost in context so that Ruby programmers
			have a little bit less to absorb if they are going to try
			experimenting with Rebol

		!!!WARNING!!!

		This is so far a one-day hack that I'm just trying to put out for
		people to look at.  It might be a good tool and people might respond
		well to it.  At least it could focus certain conversations!
    }

    Author: "Hostile Fork"
    Home: http://hostilefork.com
    License: mit

    File: %rubol.reb
    Date: 9-Nov-2009
    Version: 0.1.0

    ; Header conventions: http://www.rebol.org/one-click-submission-help.r
    Type: function
    Level: intermediate
    
    Usage: { 
		See accompanying demo files.
    }

    History: [
        0.1.0 [9-Nov-2009 {Private deployment to Rebol community} "Fork"]
    ]
]

; I build on my experimental function with statics, but I'm sure others
; will have better suggestions for how to implement this

do %func-static.reb

; function-def implements a variant of function where you put expressions in 
; the spec and they will be handled as defaults.  This feature requires a
; departure from Rebol's policy of knowing the expected number of parameters
; in advance, and callers must pass in a block.

; if you want a caller to not require a block at the call site, you explicitly
; use none as the specDef

; REVIEW: Use parse?

find-callback: func [
	"Callback on each instance of a found item, has /deep refinement"
	haystack [block!] "Block to search."
	needle [any-type!] "Element to search for."
	callback [function!] "Function to call on each find, takes series position"
	/deep "Should recurse into blocks?"
	/local pos thing foundAny
] [
	foundAny: false
	pos: haystack
	while [not tail? pos] [
		thing: first pos
		either block? thing [
			if deep [
				foundAny: foundAny or find-callback/deep thing needle :callback
			]
			; what if needle is a block?  currently ignored, always fails
		] [
			if thing = needle [ 
				callback pos
				foundAny: true
			]
		]
		pos: next pos
  	]
	return foundAny
]


function-def: function [
	specDef [block! none!]
	body [block!]
	/with withObject
	/no-with-hack
] [

	; look for uses of yield in body
	; seems to be no find/deep
	; http://www.mail-archive.com/rebol-list@rebol.com/msg04728.html

	yieldable: find-callback/deep body 'yield func [pos] [
		change/part pos [FUNCTION-DEF.yielder reduce] 1
	]

	if none? specDef compose/deep [
		either with [
			return function/with [(either yieldable [[yield]] [[]])] body withObject
		] [
			either no-with-hack [
				return function/no-with-hack [(either yieldable [[yield]] [[]])] body
			] [
				return function [(either yieldable [[yield]] [[]])] body
			]
		]
	]

	paramInfo: get-parameter-information specDef
	functionSpec: compose/deep [func-static [
			FUNCTION-DEF.args [block!]
			(either yieldable [[FUNCTION-DEF.yielder [function! block!]]] [[]])
		] [
			FUNCTION-DEF.defaults: [(paramInfo/defaults)]
			FUNCTION-DEF.main: (
				;-- function! generator
				either with [
					[function/with]
				] [
					either no-with-hack [
						[func]
					] [
						[function]
					]
				]
			) [
				;-- parameter block
				(paramInfo/spec)
				;-- add yielder parameter if necessary
				(either yieldable [[FUNCTION-DEF.yielder [function! block!]]] [[]])
			] [
				;-- body block
				(
					either yieldable [
						;-- generate function if block passed as a yielder
						[if block? :FUNCTION-DEF.yielder [
							FUNCTION-DEF.yielder: ruby-block FUNCTION-DEF.yielder
						]]
					] [
						[]
					]
				)
				(body)
			] (
				;-- with object, if necessary
				either with [[withObject]] [[]]
			) 
		] [
			; evaluate the arguments in the caller's context
			FUNCTION-DEF.mainArgs: reduce FUNCTION-DEF.args

			; If we reduced and didn't get enough args, add from the defaults
			if lesser? length? FUNCTION-DEF.mainArgs length? FUNCTION-DEF.defaults [
				skip-length: (subtract 
					length? FUNCTION-DEF.mainArgs
					length? FUNCTION-DEF.defaults
				)
				append FUNCTION-DEF.mainArgs (
					compose skip tail FUNCTION-DEF.defaults skip-length
				)
			]

			return do append compose [
				FUNCTION-DEF.main (FUNCTION-DEF.mainArgs)
			] [(either yieldable [[:FUNCTION-DEF.yielder]] [[]])]
		] 
	]

	;print "Function specification for FUNCTION-DEF translated into funct-static"
	;probe functionSpec
	;print newline

	return do functionSpec
]

;
; Many languages have the property that they allow two different ways of
; defining things.  One for anonymous things, another for things with names:
;
;    (style 1)  function myFunction (a, b) { ... }
;    (style 2)  myFunction = function (a, b) { ... }
;
; Rebol's expectation of knowing the number of parameters in advance doesn't
; really permit this, although with refinements you could do:
;
;    function/named [a b] [ ... ] myFunction
;    myFunction: function [a b] [ ... ]
;
; (The reverse case of having a /anonymous refinement does not work because
; refinements can add parameters but they cannot subtract them.)
;
; Clearly it was possible in these languages to have uniformly used style 2, as
; Rebol does.  Yet there was a conscious decision to incorporate style 1 even
; though it is less "uniform".  I believe this has to do with the desire of
; programmers to differentiate between declaration and assignment.
;
; There is a workaround possibility in Rebol:
;
;    function myFunction [a b] [ ...]
;    myFunction: function anonymous [a b] [ ... ]
;
; The anonymous word would signify to the abstraction that it is not to set a
; name.  While anonymous is a little bit wordy, it's fairly obvious and more
; literate (while words like "noname" are hard to scan).
;
; We could call this pattern declare, but "var" is short and familiar:
;
;    >> var a (1 + 1)
;    == 2
;
;    >> probe a
;    2
;    == 2
;
; If you pass in a block, it will evaluate as if you had written that block out
; after a set-word.
;
;    >> var b [reverse "hello"]
;    == "olleh"
;
;    >> print b
;    olleh
;
; The caveat is that such declarations are not seen by scans for set-words.
; This interferes with abstractions that assume all set-words are at source
; level (e.g. function).
; 
; It is a stopgap measure to ease compatibility for certain things like classes
; which must know their name in Rubol.  To get the usual benefit of being a set
; word, the equivalent:
;
;    c: make-class [ ... ]
;    d: make-def [ ... ]
;
; ...should be used instead when possible.
;

var: func ['varName [word!] args] [
	either varName = 'anonymous [
		do args
	] [
		do append reduce [to-set-word varName] args
	]
]


;
; These would be nice...
; ...but shorthand does not exist... yet?
;
;    yield: make shorthand! [FUNCTION-DEF.yielder reduce]
;    def: make shorthand! [def-core self]
;    

class: func ['className blk [block!] "Object words and values."] [
	var className [make-class/named blk to-string className]
]

make-class: function [
	blk [block!] "Object words and values."
	/named className [string!] "Optional class name for this class"
] [
	;
	; Everywhere they say
	;
	;	def x [spec] [body]
	;
	; what we really want to do is
	;
	; 	def-core self [spec] [body]
	;
	; It does not seem possible to make def capture self within the object
	; without explicit parameterization
	;

	;
	; New feature is to scan for whether they use any yield statements.
	; If so, we make:
	;
	; 	FUNCTION-DEF/with/yieldable [spec] [body] self
	;
	; That makes a refinement on the generated function whose argument is
	; named yield.  Hence yield isn't really an operator, it's the name of
	; the invisible parameter
	;

	;
	; Also everywhere they say:
	;
	;	attr_accessor .foo
	;
	; we want to change this into
	;
	;	foo: object [set: ... get: ...]
	;
	; there's also a variant that will do this for several attributes
	;
	; 	attr_accessor [.foo .bar .baz]
	;

	;
	; The parse dialect can handle this although I thought there was a more
	; elegant form of change.  It apparently isn't working...
	;
	; 	http://curecode.org/rebol3/ticket.rsp?id=1279&cursor=11
	;
	; Also the details of how to get it work in one pass are bogging me down
	; so I will leave that to someone else for now, this should all be possible
	; more elegantly.
	;

	defRule: [
		any [
			to [quote def] replaceStart: 
			4 skip replaceEnd: (
				replaceBody: first back replaceEnd 
				replaceSpec: first back back replaceEnd
				replaceName: first back back back replaceEnd

				replaceEnd: change/part replaceStart compose/only [
					(to-set-word replaceName)
					make-def-core self (replaceSpec)
					(replaceBody)
				] replaceEnd
			) :replaceEnd
		] to end
	]

	protectAccessors: copy []

	attr_accessorRule: [
		any [
			to [quote attr_accessor] replaceStart: 
			skip [word! | block!] replaceEnd: (
				replaceArg: first back replaceEnd
				if word? replaceArg [
					replaceArg: to-block replaceArg
				]
				replaceWith: copy []
				foreach attributeRef replaceArg [
					use [attributeWithoutDot] [
						attributeNameWithoutDot: next to-string attributeRef
						append protectAccessors 'protect
						append protectAccessors to-lit-word attributeNameWithoutDot
						append replaceWith compose/deep [
							(to-set-word attributeNameWithoutDot) object [
								set: func [value] [(to-set-word attributeRef) value]
								get: func [] [(attributeRef)]
							]
						]
					]
				]
				replaceEnd: change/part replaceStart replaceWith replaceEnd 
			) :replaceEnd
		] to end
	]

	; REVIEW: throw if this does not succeed?
	; TODO: unify so it's one parse pass?
	parse blk defRule
	parse blk attr_accessorRule

	; collect the set-words at the first level of the spec
	; these are the member functions and declared members

	explicitMembers: collect-words/set blk

	; get all the assignments that are at deeper levels
	; NOTE: this picks up defs too.  should check to make sure
	; they're not using dots?

	localAssignments: collect-words/deep/set/ignore blk explicitMembers

	; produce a list of implicit members that we saw
	; used in assignments whose names start with a period
	; We will explicitly add them to the object so that Rebol 
	; treats them as members.

	implicitMembers: copy []
	foreach w localAssignments [
		if (first to-string w) == #"." [
			append implicitMembers compose [
				(to-set-word w) none
			]
		]
	]

	; give the meta-class object a member "new" which is a function 
	; that will instantiate a Rebol object

	return do reduce [
		object compose/deep [
			new: func [args [block!] /local newObject] [
				newObject: object [
					class: object [name: (className)]
					(implicitMembers)
					(blk)
					(protectAccessors)
				]

				;probe newObject

				newObject/initialize args
				return newObject
			]
		]
	]
]

;
; def also comes in def and make-def variants
;

def: func ['defName spec [none! block!] body [block!]] [
	var defName [make-def/named spec body to-string defName]
]

make-def: func [spec [none! block!] body [block!] /named defName [string!]] [
	either named [
		make-def-core/named none spec body defName
	] [
		make-def-core none spec body
	]
]

;
; Ruby's def works in classes to have access to class members, and outside to
; act like a function that has access to context.  Unfortunately outside of a
; class we cannot grab the self without something like shorthand! ... so for
; now your function cannot grab variables from context *unless* inside a class.
; To hack around that you can use:
;
;     make-def-core self  (....) self
;
; This works inside classes, which will convert def or make-def into
; make-def-core during their creation.  Outside of classes, however, it won't
; work.  I have proposed a fix:
;
;    make-def: make shorthand! [make-def-core spec]
;

def-core: func [me [object!] 'defName spec [none! block!] body [block!]] [
	var defName [make-def-core me spec body to-string defName]
]

make-def-core: func [
	me [none! object!]
	spec [none! block!]
	body [block!]
	/named defName [string!]
] [
	; for now we ignore defName, but does Ruby need it for RTTI?

	either none? me [
		; since we cannot automatically capture the self from our context
		; this is currently needed to be a func if used in global scope.
		; a fairly nasty hack which could be finessed with shorthand! or
		; perhaps another technique

		FUNCTION-DEF/no-with-hack spec body
	] [
		FUNCTION-DEF/with spec body me
	]
]

; Ruby has an operation called puts that calls the to_s method on the passed in
; object explicitly.

puts: func [arg] [
	either object? arg [
		print arg/to_s
	] [
		print to-string arg
	]
]

; I'm not entirely sure what the difference between Ruby's print and puts is,
; but it's clear that print doesn't put out a newline.  That corresponds to
; Rebol's "prin"

ruby-print: func [arg] [
	either object? arg [
		prin arg/to_s
	] [
		either block? arg [
			prin rejoin arg
		] [
			prin to-string arg
		]
	]
]

; Note that when you put a colon on the end of a token, it's a "set-word"
; (e.g. an assignment).  But when you put a colon at the *beginning*
; of a word it becomes a "get-word".  This lets us differentiate
; between the desire to call the print function vs. fetching the
; function object itself.

; so you should read...
;
;     foo: :bar
;
; ...as "set the foo word to what the bar word is currently pointing to"

; Ruby uses nil, why not define it just to reduce speed bumps...?

nil: :none
nil?: :none?

; Ruby has a "join" method already, and although we could overwrite it with
; the Ruby notion of joining this seems better

ruby-join: func [iterable [series!] separator /local pos] [
	result: copy ""
	if not empty? iterable [
		pos: head iterable
		while [not tail? next pos] [
			append result to-string first pos
			append result separator
			pos: next pos
		]
		append result to-string first pos
	]
]

; Ruby has do which is a function generator, not a code evaluator.  Currently 
; making it equivalent to a FUNCTION-DEF with no /with refinement

ruby-do: :does


; Ruby's notion of a "code block" is a fast way to write functions, but really
; equivalent to a more verbose form.
;
;    { |last,first| print "employee ",": ",first, " ",last}
;
; That's really no different from:
;
;    def (last, first) print "employee",": ",first," ", last end
;
; There is some contention among Ruby programmers as to when to use this
; abbreviated notation.  But as with other things in Rubol, our job is not
; to question why they like this -- just to show that it can be captured in
; spirit without too much trouble.  The way to make such a function
; in Rubol is:
;
;    ruby-block [ [last first] ... ]
;
; If the first element is a block, it is assumed to be the spec block.  If you
; actually want the first piece of your code to be a block, then make sure to
; include an empty block at the start.
;
; (Code in the ... obviously will be a little different)

; From http://www.devarticles.com/c/a/Ruby-on-Rails/Code-Blocks-and-Iteration/
;
; Arguments to blocks look almost like arguments to methods, but there are a
; few restrictions: you cannot set default values for block arguments, you
; cannot expand hashes or arrays inline, and a block cannot itself take a
; block argument.*

; Hey, no defaults.  So we don't have to use def!  func is more efficient.
; We still want to use blocks to pass parameters in order to make the lambda
; compatible with make-def.  If they want a func!, they'll use func!

ruby-lambda: func [code [block!] /local assignments index] [
	either block? first code [
		assignments: copy []
		index: 1
		foreach arg first code [
			repend assignments compose [
				(to-set-word arg) pick RUBY-LAMBDA.args (index)
			]
			index: index + 1
		]
		return func [RUBY-LAMBDA.args [block!]] append assignments next code
	] [
		return func [] code
	]

; Does it allow defaults?  If not, we can optimize.  In fact make-def
; can optimize down to a function.  Hm.

;	if empty? code [
;		return make-def [] []
;	]
;	either block? first code [
;		return make-def first code copy next code
;	] [
;		return make-def [] code
;	]
]


; Ruby's "times" is repeat only it takes functions made with do and not
; blocks
; 
; count = 0
; 5.times do 
;   count += 1
;   puts "count = " + count_to s
; end

ruby-times: func [expr what [function!]] [
	loop expr [what]
]

; Ruby has the ability to define ranges.  We don't want to produce a whole
; series out of a range but rather a function that can count for us.  They use
; two dots to mean "up to and including value" and three dots to mean "up to
; value but not including".  (Seems backwards to me, but it is what it is.)
; Originally I called this "range" but changed to ruby-in to make it more
; compatible with the appearance of Ruby's for loops

; UPDATE: Ruby apparently optimizes for the range case more than just using a
; function.  This will have be tuned for performance, perhaps by returning an
; object which the ruby-each-core can probe for the range start and range end
; and then run in a tight loop...

ruby-in: func [span [block!]] [
	if not found? second span [.. ...] [
		throw make error! "second element of ruby-in block must be .. or ..."
	]
	
	object [
		RUBY-IN.minValue: first span
		RUBY-IN.maxValue: third span + either '.. = second span [1] [0]
		RUBY-IN.state: none
		; Need to look deeper into guts of Ruby's enumeration methods
		; but for now we have resetIteration and getNext
		resetIteration: func [] [
			state: none
		]
		getNext: func [] [
			either none? RUBY-IN.state [
				RUBY-IN.state: RUBY-IN.minValue
			] [
				RUBY-IN.state: RUBY-IN.state + 1
			]

			either RUBY-IN.state < RUBY-IN.maxValue [
				RUBY-IN.state ; <-- return
			] [
				resetIteration
				none ; <-- return
			]
		]
	] ; <-- return
]

; Ruby has each which works with generative objects (e.g. ranges) as well as
; series.  This is the generalized iterator logic

; you provide it with a function that takes the value.
; returning true continues the iteration, returning false stops it

ruby-each-core: func [
	iterable [block! series! object!] 
	action [function!] 
	/local pos value minValue maxValue
] [
	if object? :iterable [
		; We specifically recognize ranges that were initialized with "ruby-in"
		; in order to avoid the overhead of calling a getNext function on each
		; loop.  They are also iterable, but this is an efficiency trick.
		if in iterable 'RUBY-IN.minValue [
			minValue: iterable/RUBY-IN.minValue
			maxValue: iterable/RUBY-IN.maxValue
			value: minValue
			while [value < maxValue] [
				either action value [
					++ value
			 	] [
			 		return none
			 	]
			]
			return none
		]
		
		if (in iterable 'resetIteration) and (in iterable 'getNext) [
			iterable/resetIteration
			while [not none? value: iterable/getNext] [
				if not action value [
			 		return none
				]
			]
			iterable/resetIteration
			return none
		]
		
		; Otherwise, take the getNext member
		iterable: :iterable/getNext
	]

	if not function? :iterable [
		pos: iterable
	]

	either function? :iterable  [
		
	] [
		while [not tail? pos] [
			if not action first pos [
				return none
			]
			pos: next pos
		]
	]
	none ; <-- returned
]

ruby-each: func [iterable [block! series! object!] f [block! function!]] [
	if block? f [
		f: ruby-lambda f
	]
	ruby-each-core :iterable func [value] [
		f append/only copy [] value 
		true ; <-- returned
	]
	none ; <-- returned
]

; detect gives back the first item matching a logical expression, e.g. the
; function we run returns a boolean saying whether we match.

ruby-detect: function [
	iterable [block! series! object!]
	f [block! function!]
] [
	if block? f [
		f: ruby-lambda f
	]
	
	result: none
	ruby-each-core :iterable func [value] [
		either f append/only copy [] value [
			result: value
			false ; <-- returned
		] [
			true ; <-- returned
		]
	]
	return result
]

; select is like detect but returns a block of matches

ruby-select: function [
	iterable [block! series! object!]
	f [block! function!]
] [
	if block? f [
		f: ruby-lambda f
	]

	results: copy []
	ruby-each-core :iterable func [value] [
		if f append/only copy [] value [
			append/only results value
		] 
		true ; <-- returned
	]
	return results
]


;
; Ruby's inject is an operation that loops over the values in the iterable
; object, calling a function on each iteration which takes two values.  The
; first value is the result that came from the previous call.  The second value
; is the current element being iterated.
;
; To deal with the question of what the first parameter is when you call on the
; first element, there are two options.  The default is that you skip the first
; element entirely and just make it the first parameter to the call for the
; second element.
;
; The second option is to supply an initial value which is fed to the call with
; the first element, and we specify that using a refinement (/initial)
;

ruby-inject: func [
	iterable [block! series! object!] 
	f [block! function!] 
	/initial init 
	/local lastResult needsInit
] [
	if block? f [
		f: ruby-lambda f
	]

	lastResult: init ; may be none (if false? initial)
	needsInit: true? initial
		
	ruby-each-core :iterable func [value] [
		either needsInit [
			lastResult: value
			needsInit: false
		] [
			lastResult: f reduce [lastResult value]
		]
		true ; <-- returned
	]
	
	lastResult ; <-- returned
]

;
; Ruby can collect the items from an iterable object into an array, optionally 
; running a function on each item.  It can do this forward or reverse.
; We use a refinement instead of a separate keyword for reversal (/backwards)
; but in the case where they do not want to run a function they should call
; with none.
;
; (Using /backwards because reverse is a keyword)
;

ruby-collect: function [
	iterable [block! series! object!]
	f [block! function! none!] 
	/backwards
] [
	if block? f [
		f: ruby-lambda f
	]
	results: copy []
	
	ruby-each-core :iterable func [value] [
		insert-pos: either backwards [head results] [tail results]
		either none? :f [
			insert/only insert-pos value
		] [
			insert/only insert-pos (f append/only copy [] value) 
		]
		true
	]
	return results 
]

; Ruby's for is a lot like it's each, just slightly different syntax
; http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-talk/132518
; In Rubol we make them equivalent.  In fact, you must use ruby-in to
; turn a block parameter into a range.

ruby-for: :ruby-each

; To help make compatible example output, rather than print out things
; like "make map!" it's easy enough to match Ruby so why not?  add
; more types...

ruby-p: func [arg [map!] /local result temp] [
	result: none
	foreach [key value] arg [
		either none? result [
			result: copy "{"
		] [
			append result ", "
		]
		append result rejoin [mold key "=>" mold value]
	]
	append result "}"
	print result
]

;
; The current policy is to let Ruby keywords be defined in the global namespace
; if no Rebol equivalent word exists.  Something similar to the secure policy
; language might be good for turning on and off the keywords... and allowing
; users to override things like "do" and "join" but then put them back to the
; defaults later.
;

lambda: :ruby-lambda
times: :ruby-times
each: :ruby-each
detect: :ruby-detect
inject: :ruby-inject
p: :ruby-p
