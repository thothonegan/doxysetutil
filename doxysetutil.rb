#!/usr/bin/env ruby

require 'fileutils'
require 'nokogiri' # XML
require 'optparse'
require 'sqlite3'

OPTIONS = {
	:localization => nil,
	:skipText => false,
	:skipAPI => false,
	:node => nil,
	:verbose => false,
	:debug => false
}

# returns the ID of the node created
def p_createNodeAndChildren (db, node, primaryParentID, prefix)
	name = node.xpath('./Name').text
	path = node.xpath('./Path').text
	anchor = node.xpath('./Anchor')
	if anchor != nil
		anchor = anchor.text
	end
	
	if OPTIONS[:debug]
		STDERR.puts "#{prefix} Processing #{name}"
	end
	
	# integer - not sure what format it is
	checksum = nil
	nodeID = nil # will reconnect later
	baseurl = nil
	filename = nil
	
	db.execute("INSERT INTO ZNODEURL (Z_ENT, Z_OPT, ZCHECKSUM, ZNODE, ZANCHOR, ZBASEURL, ZFILENAME, ZPATH) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
		9, 1, checksum, nodeID,
		anchor, baseurl, filename, path
		
	)
	nodeURLID = db.last_insert_row_id
	
	isSearchable = 1
	nodeType = 1
	kID = nil # no idea what it is : it tends to be really negative numbers
	subNodeCount = 0 # we'll fix this later once we know the count
	
	db.execute("INSERT INTO ZNODE (Z_ENT, Z_OPT, ZINSTALLDOMAIN, ZKDOCUMENTTYPE, ZKID, ZKISSEARCHABLE, ZKNODETYPE, ZKSUBNODECOUNT, ZPRIMARYPARENT, ZKNAME) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
		8, 2, 1, 0,
		kID, isSearchable, nodeType, subNodeCount,
		primaryParentID, name
	)
	nodeID = db.last_insert_row_id
	
	# update nodeURL
	db.execute("UPDATE ZNODEURL SET ZNODE=? WHERE Z_PK=?", nodeID, nodeURLID)
	
	# handle children
	children = node.xpath('./Subnodes/Node')
	childrenCount = children.count
	childrenIndex = 0
	
	children.each do |subnode|
		childrenIndex += 1
		subNodeID = p_createNodeAndChildren(db, subnode, nodeID, prefix + "[#{childrenIndex}/#{childrenCount}]")
		
		# create the subnode link
		# ordering starts at 1
		db.execute("INSERT INTO ZORDEREDSUBNODE (Z_ENT, Z_OPT, ZORDER, ZNODE, ZPARENT) VALUES (?, ?, ?, ?, ?)",
			11, 1, subNodeCount+1, subNodeID, nodeID
		)
		subNodeCount += 1
	end
	
	# update node with the final count
	db.execute("UPDATE ZNODE SET ZKSUBNODECOUNT=? WHERE Z_PK=?", subNodeCount, nodeID)
	
	# done
	return nodeID
end



# Works similar to docsetutil
# See http://www.manpagez.com/man/1/docsetutil/ though we dont support all verbs
HELP_BANNER="Usage: doxysetutil [verb] [options] [docsetpath]"
if ARGV.count == 0
	STDERR.puts HELP_BANNER
	exit 1
end

parser = OptionParser.new do |parser|
	parser.banner = HELP_BANNER
	parser.on '-localization=LOC', 'Perform the operation using a particular localization' do |localization|
		OPTIONS[:localization] = localization
	end

	parser.on '-skip-text', 'Do not perform the operation for the full-text index.' do |skipText|
		OPTIONS[:skipText] = skipText
	end

	parser.on '-skip-api', 'Do not perform the operation for the API index.' do |skipAPI|
		OPTIONS[:skipAPI] = skipAPI
	end

	parser.on '-node=NODEPATH', 'Perform the operation only on the documents that reside at or below a location via a : named list' do |node|
		OPTIONS[:node] = node
	end
	
	parser.on '-verbose', 'Print out addictional information about the operation being performed.' do |v|
		OPTIONS[:verbose] = v
	end
	
	parser.on '-debug', 'Print out debugging information' do |d|
		OPTIONS[:debug] = d
	end
end

parser.parse!

verb = ARGV[0]
docsetPath = nil
if ARGV.count >= 2
	docsetPath = ARGV[1]
end

if verb == 'help'
	STDERR.puts parser.help
	
	STDERR.puts ""
	
	STDERR.puts "Verbs:"
	STDERR.puts "- help : Displays help about the tool"
	STDERR.puts "- index: Converts the XML files into a searchable index"
	STDERR.puts "- search: (not implemented) Search the full text and API indexes for the specified terms"
	STDERR.puts "- validate: (not implemented) Examines the indexes for all files referenced and verifies that those files exist."
	STDERR.puts "- dump: (not implemented) Print out the contents of the indexes"
	STDERR.puts "- package: (not implemented) Generate an archive of the documentation."
	
	exit 1

elsif verb == 'index'
	# First delete any current index
	indexPath = "#{docsetPath}/Contents/Resources/docSet.dsidx"
	nodesXMLFile="#{docsetPath}/Contents/Resources/Nodes.xml"
	tokensXMLFile="#{docsetPath}/Contents/Resources/Tokens.xml"
	
	if OPTIONS[:verbose] || OPTIONS[:debug]
		STDERR.puts "Creating index #{indexPath} from #{nodesXMLFile} and #{tokensXMLFile}"
	end
	
	FileUtils.rm indexPath, :force => true
	
	db = SQLite3::Database.new indexPath
	
	# we try to copy a similar system to docsetutil, so we built other classes and use a view for the main table
	# even though we're not coredata
	db.execute_batch <<-ENDSQL
		CREATE TABLE ZAPILANGUAGE ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZFULLNAME VARCHAR );
		CREATE TABLE Z_1NODES ( Z_1APILANGUAGES INTEGER, Z_8NODES INTEGER, PRIMARY KEY (Z_1APILANGUAGES, Z_8NODES) );
		CREATE TABLE ZCONTAINER ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZCONTAINERNAME VARCHAR );
		CREATE TABLE Z_2ADOPTEDBY ( Z_2PROTOCOLCONTAINERS INTEGER, Z_14ADOPTEDBY INTEGER, PRIMARY KEY (Z_2PROTOCOLCONTAINERS, Z_14ADOPTEDBY) );
		CREATE TABLE Z_2SUBCLASSEDBY ( Z_2SUPERCLASSCONTAINERS INTEGER, Z_14SUBCLASSEDBY INTEGER, PRIMARY KEY (Z_2SUPERCLASSCONTAINERS, Z_14SUBCLASSEDBY) );
		CREATE TABLE ZDISTRIBUTIONVERSION ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZARCHITECTUREFLAGS INTEGER, ZDISTRIBUTIONNAME VARCHAR, ZVERSIONSTRING VARCHAR );
		CREATE TABLE Z_3REMOVEDAFTERINVERSE ( Z_3REMOVEDAFTERVERSIONS INTEGER, Z_16REMOVEDAFTERINVERSE INTEGER, PRIMARY KEY (Z_3REMOVEDAFTERVERSIONS, Z_16REMOVEDAFTERINVERSE) );
		CREATE TABLE Z_3INTRODUCEDININVERSE ( Z_3INTRODUCEDINVERSIONS INTEGER, Z_16INTRODUCEDININVERSE INTEGER, PRIMARY KEY (Z_3INTRODUCEDINVERSIONS, Z_16INTRODUCEDININVERSE) );
		CREATE TABLE Z_3DEPRECATEDININVERSE ( Z_3DEPRECATEDINVERSIONS INTEGER, Z_16DEPRECATEDININVERSE INTEGER, PRIMARY KEY (Z_3DEPRECATEDINVERSIONS, Z_16DEPRECATEDININVERSE) );
		CREATE TABLE ZDOCSET ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZROOTNODE INTEGER, ZCONFIGURATIONVERSION VARCHAR );
		CREATE TABLE ZDOWNLOADABLEFILE ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZTYPE INTEGER, ZNODE INTEGER, ZURL VARCHAR );
		CREATE TABLE ZFILEPATH ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZPATH VARCHAR );
		CREATE TABLE ZHEADER ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZFRAMEWORKNAME VARCHAR, ZHEADERPATH VARCHAR );
		CREATE TABLE ZNODE ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZINSTALLDOMAIN INTEGER, ZKDOCUMENTTYPE INTEGER, ZKID INTEGER, ZKISSEARCHABLE INTEGER, ZKNODETYPE INTEGER, ZKSUBNODECOUNT INTEGER, ZPRIMARYPARENT INTEGER, ZKNAME VARCHAR );
		CREATE TABLE Z_8RELATEDNODESINVERSE ( Z_8RELATEDNODES INTEGER, Z_8RELATEDNODESINVERSE INTEGER, PRIMARY KEY (Z_8RELATEDNODES, Z_8RELATEDNODESINVERSE) );
		CREATE TABLE Z_8RELATEDDOCSINVERSE ( Z_8RELATEDDOCUMENTS INTEGER, Z_16RELATEDDOCSINVERSE INTEGER, PRIMARY KEY (Z_8RELATEDDOCUMENTS, Z_16RELATEDDOCSINVERSE) );
		CREATE TABLE Z_8RELATEDSCINVERSE ( Z_8RELATEDSAMPLECODE INTEGER, Z_16RELATEDSCINVERSE INTEGER, PRIMARY KEY (Z_8RELATEDSAMPLECODE, Z_16RELATEDSCINVERSE) );
		CREATE TABLE ZNODEURL ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZCHECKSUM INTEGER, ZNODE INTEGER, ZANCHOR VARCHAR, ZBASEURL VARCHAR, ZFILENAME VARCHAR, ZPATH VARCHAR );
		CREATE TABLE ZNODEUUID ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZNODE INTEGER, ZUUID VARCHAR );
		CREATE TABLE ZORDEREDSUBNODE ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZORDER INTEGER, ZNODE INTEGER, ZPARENT INTEGER );
		CREATE TABLE ZPARAMETER ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZORDER INTEGER, Z16PARAMETERS INTEGER, ZABSTRACT VARCHAR, ZPARAMETERNAME VARCHAR );
		CREATE TABLE ZRETURNVALUE ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZABSTRACT VARCHAR );
		CREATE TABLE ZTOKEN ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZALPHASORTORDER INTEGER, ZFIRSTLOWERCASEUTF8BYTE INTEGER, ZCONTAINER INTEGER, ZLANGUAGE INTEGER, ZMETAINFORMATION INTEGER, ZPARENTNODE INTEGER, ZTOKENTYPE INTEGER, ZTOKENNAME VARCHAR, ZTOKENUSR VARCHAR );
		CREATE TABLE Z_14RELATEDGROUPS ( Z_14TOKENS INTEGER, Z_15RELATEDGROUPS INTEGER, PRIMARY KEY (Z_14TOKENS, Z_15RELATEDGROUPS) );
		CREATE TABLE Z_14RELATEDTOKENSINVERSE ( Z_14RELATEDTOKENS INTEGER, Z_16RELATEDTOKENSINVERSE INTEGER, PRIMARY KEY (Z_14RELATEDTOKENS, Z_16RELATEDTOKENSINVERSE) );
		CREATE TABLE ZTOKENGROUP ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZTITLE VARCHAR );
		CREATE TABLE ZTOKENMETAINFORMATION ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZDECLAREDIN INTEGER, ZFILE INTEGER, ZRETURNVALUE INTEGER, ZTOKEN INTEGER, ZABSTRACT VARCHAR, ZANCHOR VARCHAR, ZDECLARATION VARCHAR, ZDEPRECATIONSUMMARY VARCHAR );
		CREATE TABLE ZTOKENTYPE ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZTYPENAME VARCHAR );
		CREATE INDEX Z_1NODES_Z_8NODES_INDEX ON Z_1NODES (Z_8NODES, Z_1APILANGUAGES);
		CREATE INDEX Z_2ADOPTEDBY_Z_14ADOPTEDBY_INDEX ON Z_2ADOPTEDBY (Z_14ADOPTEDBY, Z_2PROTOCOLCONTAINERS);
		CREATE INDEX Z_2SUBCLASSEDBY_Z_14SUBCLASSEDBY_INDEX ON Z_2SUBCLASSEDBY (Z_14SUBCLASSEDBY, Z_2SUPERCLASSCONTAINERS);
		CREATE INDEX Z_3REMOVEDAFTERINVERSE_Z_16REMOVEDAFTERINVERSE_INDEX ON Z_3REMOVEDAFTERINVERSE (Z_16REMOVEDAFTERINVERSE, Z_3REMOVEDAFTERVERSIONS);
		CREATE INDEX Z_3INTRODUCEDININVERSE_Z_16INTRODUCEDININVERSE_INDEX ON Z_3INTRODUCEDININVERSE (Z_16INTRODUCEDININVERSE, Z_3INTRODUCEDINVERSIONS);
		CREATE INDEX Z_3DEPRECATEDININVERSE_Z_16DEPRECATEDININVERSE_INDEX ON Z_3DEPRECATEDININVERSE (Z_16DEPRECATEDININVERSE, Z_3DEPRECATEDINVERSIONS);
		CREATE INDEX ZDOCSET_ZROOTNODE_INDEX ON ZDOCSET (ZROOTNODE);
		CREATE INDEX ZDOWNLOADABLEFILE_ZNODE_INDEX ON ZDOWNLOADABLEFILE (ZNODE);
		CREATE INDEX ZNODE_ZKID_INDEX ON ZNODE (ZKID);
		CREATE INDEX ZNODE_ZPRIMARYPARENT_INDEX ON ZNODE (ZPRIMARYPARENT);
		CREATE INDEX Z_8RELATEDNODESINVERSE_Z_8RELATEDNODESINVERSE_INDEX ON Z_8RELATEDNODESINVERSE (Z_8RELATEDNODESINVERSE, Z_8RELATEDNODES);
		CREATE INDEX Z_8RELATEDDOCSINVERSE_Z_16RELATEDDOCSINVERSE_INDEX ON Z_8RELATEDDOCSINVERSE (Z_16RELATEDDOCSINVERSE, Z_8RELATEDDOCUMENTS);
		CREATE INDEX Z_8RELATEDSCINVERSE_Z_16RELATEDSCINVERSE_INDEX ON Z_8RELATEDSCINVERSE (Z_16RELATEDSCINVERSE, Z_8RELATEDSAMPLECODE);
		CREATE INDEX ZNODEURL_ZCHECKSUM_INDEX ON ZNODEURL (ZCHECKSUM);
		CREATE INDEX ZNODEURL_ZNODE_INDEX ON ZNODEURL (ZNODE);
		CREATE INDEX ZNODEUUID_ZNODE_INDEX ON ZNODEUUID (ZNODE);
		CREATE INDEX ZORDEREDSUBNODE_ZNODE_INDEX ON ZORDEREDSUBNODE (ZNODE);
		CREATE INDEX ZORDEREDSUBNODE_ZPARENT_INDEX ON ZORDEREDSUBNODE (ZPARENT);
		CREATE INDEX ZPARAMETER_Z16PARAMETERS_INDEX ON ZPARAMETER (Z16PARAMETERS);
		CREATE INDEX ZTOKEN_ZALPHASORTORDER_INDEX ON ZTOKEN (ZALPHASORTORDER);
		CREATE INDEX ZTOKEN_ZFIRSTLOWERCASEUTF8BYTE_INDEX ON ZTOKEN (ZFIRSTLOWERCASEUTF8BYTE);
		CREATE INDEX ZTOKEN_ZTOKENNAME_INDEX ON ZTOKEN (ZTOKENNAME);
		CREATE INDEX ZTOKEN_ZTOKENUSR_INDEX ON ZTOKEN (ZTOKENUSR);
		CREATE INDEX ZTOKEN_ZCONTAINER_INDEX ON ZTOKEN (ZCONTAINER);
		CREATE INDEX ZTOKEN_ZLANGUAGE_INDEX ON ZTOKEN (ZLANGUAGE);
		CREATE INDEX ZTOKEN_ZMETAINFORMATION_INDEX ON ZTOKEN (ZMETAINFORMATION);
		CREATE INDEX ZTOKEN_ZPARENTNODE_INDEX ON ZTOKEN (ZPARENTNODE);
		CREATE INDEX ZTOKEN_ZTOKENTYPE_INDEX ON ZTOKEN (ZTOKENTYPE);
		CREATE INDEX Z_14RELATEDGROUPS_Z_15RELATEDGROUPS_INDEX ON Z_14RELATEDGROUPS (Z_15RELATEDGROUPS, Z_14TOKENS);
		CREATE INDEX Z_14RELATEDTOKENSINVERSE_Z_16RELATEDTOKENSINVERSE_INDEX ON Z_14RELATEDTOKENSINVERSE (Z_16RELATEDTOKENSINVERSE, Z_14RELATEDTOKENS);
		CREATE INDEX ZTOKENMETAINFORMATION_ZDECLAREDIN_INDEX ON ZTOKENMETAINFORMATION (ZDECLAREDIN);
		CREATE INDEX ZTOKENMETAINFORMATION_ZFILE_INDEX ON ZTOKENMETAINFORMATION (ZFILE);
		CREATE INDEX ZTOKENMETAINFORMATION_ZRETURNVALUE_INDEX ON ZTOKENMETAINFORMATION (ZRETURNVALUE);
		CREATE INDEX ZTOKENMETAINFORMATION_ZTOKEN_INDEX ON ZTOKENMETAINFORMATION (ZTOKEN);
		CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR, Z_SUPER INTEGER, Z_MAX INTEGER);
		CREATE TABLE Z_METADATA (Z_VERSION INTEGER PRIMARY KEY, Z_UUID VARCHAR(255), Z_PLIST BLOB);
		CREATE TABLE Z_MODELCACHE (Z_CONTENT BLOB);
		CREATE INDEX __zi_name0001 ON ztoken (ztokenname COLLATE NOCASE);
		CREATE VIEW searchIndex AS  SELECT    ztokenname AS name,    ztypename AS type,    zpath AS path,    zanchor AS fragment  FROM ztoken  INNER JOIN ztokenmetainformation    ON ztoken.zmetainformation = ztokenmetainformation.z_pk  INNER JOIN zfilepath    ON ztokenmetainformation.zfile = zfilepath.z_pk  INNER JOIN ztokentype    ON ztoken.ztokentype = ztokentype.z_pk
	ENDSQL
	
	# We have two files to read : Nodes.xml and Tokens.xml
	nodesXML = File.open(nodesXMLFile) { |f| Nokogiri::XML(f) }
	tokensXML = File.open(tokensXMLFile) { |f| Nokogiri::XML(f) }

	if OPTIONS[:debug]
		STDERR.puts "Processing tokens..."
	end
	
	# will contain values we've seen and put in the DB already
	languageIDs = []
	tokenTypes = []
	filePaths = []
	headers = []
	containers = []
	
	foundTokens = tokensXML.xpath("//Token")
	tokenCount = 0
	tokenTotal = foundTokens.count
	
	foundTokens.each do |token|
		tokenCount += 1
		
		tokenIdentifier = token.xpath("./TokenIdentifier")
		tokenIdentifierName = tokenIdentifier.xpath("./Name").text
		
		if OPTIONS[:debug]
			STDERR.puts "[#{tokenCount}/#{tokenTotal}] Processing token: #{tokenIdentifierName}"
		end
		
		tokenIdentifierAPILanguage = tokenIdentifier.xpath("./APILanguage").text
		tokenIdentifierType = tokenIdentifier.xpath("./Type").text
		path = token.xpath("./Path").text
		anchor = token.xpath("./Anchor").text
		declaredIn = token.xpath("./DeclaredIn").text
		
		tokenIdentifierScope = tokenIdentifier.xpath("./Scope")
		if tokenIdentifierScope != nil
			tokenIdentifierScope = tokenIdentifierScope.text
		end
		
		abstract = token.xpath("./Abstract")
		if abstract != nil
			abstract = abstract.text
		end
		
		# inserting
		if !languageIDs.include?(tokenIdentifierAPILanguage)
			# always appears to be 1,1
			db.execute("INSERT INTO ZAPILANGUAGE (Z_ENT, Z_OPT, ZFULLNAME) VALUES (?, ?, ?)",
				1, 1, tokenIdentifierAPILanguage
			)
			
			languageIDs << tokenIdentifierAPILanguage
		end
		
		if !tokenTypes.include?(tokenIdentifierType)
			# always appears to be 17,1
			db.execute("INSERT INTO ZTOKENTYPE (Z_ENT, Z_OPT, ZTYPENAME) VALUES (?, ?, ?)",
				17, 1, tokenIdentifierType
			)
			
			tokenTypes << tokenIdentifierType
		end
		
		if !filePaths.include?(path)
			db.execute("INSERT INTO ZFILEPATH (Z_ENT, Z_OPT, ZPATH) VALUES (?, ?, ?)",
				6, 1, path
			)
		end
		
		if !filePaths.include?(declaredIn)
			db.execute("INSERT INTO ZHEADER (Z_ENT, Z_OPT, ZFRAMEWORKNAME, ZHEADERPATH) VALUES (?, ?, ?, ?)",
				7, 1,
				nil, declaredIn
			)
		end
		
		if !containers.include?(tokenIdentifierScope)
			db.execute("INSERT INTO ZCONTAINER (Z_ENT, Z_OPT, ZCONTAINERNAME) VALUES (?, ?, ?)",
				2, 1, tokenIdentifierScope
			)
		end
		
		returnValue = nil # always null
		token = nil # we'll add after the fact to link back
		declaration = ""
		deprecationSummary = ""
		
		# create metainformation
		db.execute("INSERT INTO ZTOKENMETAINFORMATION (Z_ENT, Z_OPT, ZDECLAREDIN, ZFILE, ZRETURNVALUE, ZTOKEN, ZABSTRACT, ZANCHOR, ZDECLARATION, ZDEPRECATIONSUMMARY) " +
			" VALUES (?, ?, (SELECT Z_PK FROM ZHEADER WHERE ZHEADERPATH = ?), (SELECT Z_PK FROM ZFILEPATH WHERE ZPATH = ?), ?, ?, ?, ?, ?, ?)",
			16, 1,
			declaredIn, path, returnValue, token, abstract, anchor, declaration, deprecationSummary
		)
		metaInformationID = db.last_insert_row_id

		# create token
		# TODO: alphasort seems to be an ordering column on the data, probably sorted?
		alphaSort = nil
		firstLowerCaseUTF8Byte = tokenIdentifierName.downcase[0].ord
		parentNode = nil # always appears to be, at least
		
		db.execute("INSERT INTO ZTOKEN (Z_ENT, Z_OPT, ZALPHASORTORDER, ZFIRSTLOWERCASEUTF8BYTE, ZCONTAINER, ZLANGUAGE, ZMETAINFORMATION, ZPARENTNODE, ZTOKENTYPE, ZTOKENNAME, ZTOKENUSR) VALUES (?, ?, ?, ?, (SELECT Z_PK FROM ZCONTAINER WHERE ZCONTAINERNAME=?), (SELECT Z_PK FROM ZAPILANGUAGE WHERE ZFULLNAME=?), ?, ?, (SELECT Z_PK FROM ZTOKENTYPE WHERE ZTYPENAME=?), ?, ?)",
			14, 2,
			alphaSort, firstLowerCaseUTF8Byte, tokenIdentifierScope, tokenIdentifierAPILanguage, metaInformationID, parentNode, tokenIdentifierType, tokenIdentifierName, ""
		)
		tokenID = db.last_insert_row_id
		
		# connect the other direction
		db.execute("UPDATE ZTOKENMETAINFORMATION SET ZTOKEN=? WHERE Z_PK=?",
			tokenID, metaInformationID
		)
		
	end
	
	if OPTIONS[:debug]
		STDERR.puts "Processing nodes..."
	end
	
	# Now handle nodes
	
	rootNodeID = nil
	nodesXML.xpath("/DocSetNodes/TOC/Node").each do |node|
		rootNodeID = p_createNodeAndChildren(db, node, nil, "")
	end
	
	# Finally, docset metadata
	db.execute("INSERT INTO ZDOCSET (Z_ENT, Z_OPT, ZROOTNODE, ZCONFIGURATIONVERSION) VALUES (?, ?, ?, ?)",
		4, 1, rootNodeID, "1.0"
	)
	
	# and we're done
else
	STDERR.puts "Unknown/Not implemented verb '#{verb}'. See 'help'."
	exit 1
end

