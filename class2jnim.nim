# class2nim.nim
# Converts Java classes to Nim jnim bindings using JSON output from Java parser
# Simple and clean

import os, strutils, sequtils, tables, json, parseopt

type
  ClassDef = object
    name: string
    packageName: string
    fullName: string
    methods: seq[MethodDef]
    fields: seq[FieldDef]
    nestedClasses: seq[ClassDef]
    superClass: string
    isInterface: bool
  
  MethodDef = object
    name: string
    returnType: string
    params: seq[ParamDef]
    isPublic: bool
    isStatic: bool
  
  ParamDef = object
    typeName: string
    name: string
  
  FieldDef = object
    name: string
    fieldType: string
    isPublic: bool
    isStatic: bool

let javaToNimTypes = {
  "void": "",
  "boolean": "jboolean",
  "byte": "jbyte",
  "char": "jchar",
  "short": "jshort", 
  "int": "jint",
  "long": "jlong",
  "float": "jfloat",
  "double": "jdouble",
  "String": "string",
  "java.lang.String": "string",
  "Object": "JObject",
  "java.lang.Object": "JObject",
}.toTable

proc mapJavaTypeToNim(javaType: string): string =
  # Clean up the type string
  var cleanType = javaType.strip()
  
  # Check for generic type parameters
  var genericParams = ""
  if cleanType.contains("<") and cleanType.contains(">"):
    let startIdx = cleanType.find('<')
    let endIdx = cleanType.rfind('>')
    if startIdx > 0 and endIdx > startIdx:
      # Extract generic type parameters
      let params = cleanType[startIdx+1 .. endIdx-1]
      var paramList: seq[string] = @[]
      for param in params.split(','):
        paramList.add(mapJavaTypeToNim(param.strip()))
      
      genericParams = "[" & paramList.join(", ") & "]"
      cleanType = cleanType[0 .. startIdx-1]  # Remove generic part for now
  
  # Basic primitives 
  if cleanType in javaToNimTypes:
    return javaToNimTypes[cleanType] & genericParams
  
  # Array types
  if cleanType.endsWith("[]"):
    let baseType = cleanType[0..^3].strip()
    return "seq[" & mapJavaTypeToNim(baseType) & "]"
  
  # Handle nested classes - convert Java's $ syntax to Nim's dot syntax for types
  if cleanType.contains("$"):
    let parts = cleanType.split('$')
    # For a type like java.util.Map$Entry, we want to use java.util.Map.Entry
    cleanType = parts.join(".")
  
  # Just pass through the type as-is - no complex mapping
  return cleanType & genericParams

proc generateJnimBinding(cls: ClassDef): string =
  var result = ""
  
  # Don't repeat imports for nested classes
  if cls.packageName.len > 0 and "." notin cls.fullName:
    result.add("import jnim\n\n")
  
  # Check if we need to handle this as a nested class with a renamed type
  var className = cls.name
  var fullClassName = cls.fullName
  var asName = ""
  
  # If this is a nested class (contains $ in Java), provide a nicer name
  if fullClassName.contains("$"):
    let parts = fullClassName.split('$')
    # Use ParentNameChildName as the "as" name for cleaner usage
    let parentParts = parts[0].split('.')
    let parentSimpleName = if parentParts.len > 0: parentParts[^1] else: parts[0]
    asName = parentSimpleName & parts[^1]  # Combine parent and child names
    fullClassName = fullClassName.replace("$", ".")  # Convert $ to . for Nim
  
  # Add package name prefix for the full class name
  fullClassName = if cls.packageName.len > 0: cls.packageName & "." & fullClassName else: fullClassName
  
  # Detect if we need generic parameters
  # For that we'd need to analyze method signatures for generic type usage
  # This is a simplified approach - we'd need more analysis for proper generics
  var genericParams = ""
  var genericTypes: seq[string] = @[]
  
  # Class definition with optional generics and "as" name
  result.add("jclass " & fullClassName)
  if genericParams.len > 0:
    result.add(genericParams)
  result.add("*")
  if asName.len > 0:
    result.add(" as " & asName)
  
  # Add parent class info
  let parentClass = if cls.superClass.len > 0 and cls.superClass != "Object" and cls.superClass != "java.lang.Object": 
                      " of " & cls.superClass
                    else:
                      " of JVMObject"
  result.add(parentClass & ":\n")
  
  # Methods
  for m in cls.methods:
    if not m.isPublic: continue
    
    var params = ""
    for i, p in m.params:
      if i > 0: params.add(", ")
      params.add(p.name & ": " & mapJavaTypeToNim(p.typeName))
    
    let returnType = if m.returnType == "void": "" else: ": " & mapJavaTypeToNim(m.returnType)
    let staticMark = if m.isStatic: " {.`static`.}" else: ""
    
    result.add("  proc " & m.name & "*(" & params & ")" & returnType & staticMark & "\n")
  
  # Fields
  for f in cls.fields:
    if not f.isPublic: continue
    let staticMark = if f.isStatic: " {.`static`.}" else: ""
    result.add("  " & f.name & "*: " & mapJavaTypeToNim(f.fieldType) & staticMark & "\n")
  
  result.add("\n")
  
  # Generate nested classes
  for nested in cls.nestedClasses:
    result.add(generateJnimBinding(nested))
  
  return result

proc parseJsonClassDef(jsonNode: JsonNode): ClassDef =
  result.name = jsonNode["name"].getStr()
  result.packageName = jsonNode["package"].getStr()
  result.fullName = jsonNode["full_name"].getStr()
  result.isInterface = jsonNode["is_interface"].getBool()
  
  # Set superclass if available
  if jsonNode.hasKey("superclass") and jsonNode["superclass"].kind != JNull:
    result.superClass = jsonNode["superclass"].getStr()
  
  # Parse methods
  if jsonNode.hasKey("methods"):
    for m in jsonNode["methods"]:
      var meth = MethodDef()
      meth.name = m["name"].getStr()
      meth.returnType = m["return_type"].getStr()
      meth.isPublic = m["modifiers"].getElems().anyIt(it.getStr() == "public")
      meth.isStatic = m["modifiers"].getElems().anyIt(it.getStr() == "static")
      
      # Parse parameters
      if m.hasKey("parameters"):
        for p in m["parameters"]:
          var param = ParamDef()
          param.typeName = p["type"].getStr()
          param.name = p["name"].getStr()
          meth.params.add(param)
      
      result.methods.add(meth)
  
  # Parse fields
  if jsonNode.hasKey("fields"):
    for f in jsonNode["fields"]:
      var field = FieldDef()
      field.name = f["name"].getStr()
      field.fieldType = f["type"].getStr()
      field.isPublic = f["modifiers"].getElems().anyIt(it.getStr() == "public")
      field.isStatic = f["modifiers"].getElems().anyIt(it.getStr() == "static")
      
      result.fields.add(field)
  
  # Parse nested classes recursively
  if jsonNode.hasKey("nested_classes"):
    for nestedJson in jsonNode["nested_classes"]:
      result.nestedClasses.add(parseJsonClassDef(nestedJson))

proc loadClassesFromJson(jsonFile: string): seq[ClassDef] =
  let jsonData = parseFile(jsonFile)
  var result: seq[ClassDef] = @[]
  
  for classJson in jsonData:
    result.add(parseJsonClassDef(classJson))
  
  return result

proc processJsonFile(jsonFile: string) =
  let outputFile = jsonFile.changeFileExt(".nim")
  
  echo "Processing: ", jsonFile, " -> ", outputFile
  
  # Load classes
  let classes = loadClassesFromJson(jsonFile)
  
  if classes.len == 0:
    echo "  No classes found, skipping"
    return
  
  # Generate Nim bindings
  var nimCode = ""
  for cls in classes:
    nimCode.add(generateJnimBinding(cls))
  
  # Write to output file
  writeFile(outputFile, nimCode)
  echo "  Generated Nim bindings: ", outputFile

proc processDirectory(dir: string) =
  echo "Scanning directory: ", dir
  
  for kind, path in walkDir(dir):
    case kind
    of pcFile:
      if path.endsWith(".json"):
        processJsonFile(path)
    of pcDir:
      processDirectory(path)  # Recurse into subdirectories
    else:
      discard  # Skip other types (symlinks, etc)

proc showHelp() =
  echo "class2nim - Convert Java classes to Nim jnim bindings"
  echo "Usage: class2nim [options] <input_file.json or directory>"
  echo "Options:"
  echo "  -o, --output <file>    Output file (only for single file mode)"
  echo "  -h, --help             Show this help"
  echo ""
  echo "Note: When processing a directory, .json files will be converted to .nim files"
  echo "      with the same name in the same location."
  echo "Example: ./class2nim output_dir  # Process all JSON files in output_dir recursively"

proc main() =
  var 
    inputPath = ""
    outputFile = ""
  
  # Parse command line args
  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      inputPath = key
    of cmdLongOption, cmdShortOption:
      case key
      of "o", "output": outputFile = val
      of "h", "help": 
        showHelp()
        quit(0)
    of cmdEnd: discard
  
  if inputPath == "":
    showHelp()
    quit(1)
  
  if not fileExists(inputPath) and not dirExists(inputPath):
    echo "Error: Input path not found: ", inputPath
    quit(1)
  
  # Process the input (file or directory)
  if dirExists(inputPath):
    processDirectory(inputPath)
  else:
    # Single file mode
    if outputFile == "":
      outputFile = inputPath.changeFileExt(".nim")
    
    let classes = loadClassesFromJson(inputPath)
    
    if classes.len == 0:
      echo "Error: No classes found in ", inputPath
      quit(1)
    
    # Generate Nim bindings
    var nimCode = ""
    for cls in classes:
      nimCode.add(generateJnimBinding(cls))
    
    # Write to output file
    writeFile(outputFile, nimCode)
    echo "Generated Nim bindings in: ", outputFile

when isMainModule:
  main()
