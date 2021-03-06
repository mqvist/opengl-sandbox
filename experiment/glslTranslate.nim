## this file is for all functions that are related to translating Nim
## directly to glsl.


##[
]##

import glm, ast_pattern_matching, macros, algorithm
import ../fancygl/boring_stuff
import ../fancygl/normalizeType
import ../fancygl/typeinfo

import hashes

proc symKind(arg: NimNode): NimSymKind =
  if arg.kind == nnkHiddenDeref:
    symKind(arg[0])
  else:
    if arg.kind != nnkSym:
      error("something")
    macros.symKind(arg)

proc isSampler*(arg: NimNode): bool =
  arg.getTypeInst.normalizeType.matchAst:
  of ident"Texture1D":
    return true
  of ident"Texture2D":
    return true
  of ident"Texture3D":
    return true
  of ident"Texture1DArray":
    return true
  of ident"Texture2DArray":
    return true
  of ident"TextureRectangle":
    return true
  of ident"TextureCubeMap":
    return true
  of ident"TextureCubeMapArray":
    return true
  of ident"TextureBuffer":
    return true
  of ident"Texture2DMultisample":
    return true
  of ident"Texture2DMultisampleArray":
    return true
  of ident"Texture1DShadow":
    return true
  of ident"Texture2DShadow":
    return true
  of ident"TextureCubeShadow":
    return true
  of ident"TextureCubeArrayShadow":
    return true
  of ident"Texture2DRectShadow":
    return true
  of ident"Texture1DArrayShadow":
    return true
  of ident"Texture2DArrayShadow":
    return true
  else:
    return false

when isMainModule:
  macro testGlslType(arg: typed): untyped =
    var expected: string
    for varSection in arg:
      if varSection.kind == nnkVarSection:
        let identDefs = varSection[0]
        let sym = identDefs[0]

        let typeInst = sym.getTypeInst
        let glslType = typeInst.glslType
        echo glslType
        assert glslType == expected
      else:
        expected = varSection.strVal

  testGlslType:
    ## vec4
    var a: Vec4f
    ## vec4
    var b: Vec4[float32]
    ## vec4
    var c: Vec[4,float32]
    ## mat4
    var d: Mat4f
    ## mat4
    var e: Mat4[float32]
    ## mat4
    var f: Mat[4,4,float32]
    ## float
    var g: float32
    ## mat3x4
    var h: Mat[3,4, float32]
    ## mat4x2
    var i: Mat[4,2, float32]

## too many local variables, and the compiler goes boom, therefore here is a totally non semanitc split of compileToGlsl.

proc compileToGlsl*(result: var string; arg: NimNode): void



const
  cb64 = [
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N",
    "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n",
    "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9a","9b","9c"]

proc pseudoBase64*(dst: var string; arg: int): void {.compileTime.} =
  ## Encode `arg` into pseudo base64 representation and append it to
  ## `dst`.  This pseudoBase64 should never be decoded again, it is
  ## just for appending symbol identifiers.
  var arg = cast[uint64](arg)
  while 0'u64 < arg:
    dst.add cb64[arg and 0x3f]
    arg = arg shr 6

#static:
#  var buffer: string = ""
#  var procCache: seq[tuple[sym: NimNode; code: string]] = @[]

proc compileProcToGlsl(result: var string; arg: NimNode): void {.compileTime.} =
  matchAst(arg):
  of nnkProcDef(`nameSym`, _, _, `params` @ nnkFormalParams, _, _, `body`, `resultSym`):
    result.add glslType(params[0]), " "
    result.compileToGlsl(nameSym)
    result.add "("
    for memberSym, typeSym in params.fields:
      result.add glslType(typeSym), " "
      result.compileToGlsl(memberSym)
      result.add ", "
    result[^2] = ')'
    result.add "{\n"
    result.add glslType(resultSym.getTypeInst), " "
    result.compileToGlsl(resultSym)
    result.add ";\n"
    result.compileToGlsl(body)
    if body.kind != nnkStmtList:
      result.add ";\n"
    result.add "return "
    result.compileToGlsl(resultSym)
    result.add ";\n}\n"

  of nnkProcDef(`nameSym`, _, _, `params` @ nnkFormalParams, _, _, `body`):
    result.add glslType(params[0]), " "
    result.compileToGlsl(nameSym)
    result.add "("
    for memberSym, typeSym in params.fields:
      result.add glslType(typeSym), " "
      result.compileToGlsl(memberSym)
      result.add ", "
    result[^2] = ')'
    result.add "{\n"
    result.add "return "
    result.compileToGlsl(body)
    result.add ";\n}\n"

proc compileToGlsl*(result: var string; arg: NimNode): void {.compileTime} =
  arg.matchAst(errorSym):
  of {nnkFloat32Lit,nnkFloat64Lit,nnkFloatLit}:
    result.add arg.floatVal
  of {nnkInt32Lit, nnkInt64Lit, nnkIntLit}:
    result.add arg.intVal
  of nnkEmpty:
    result.add "/* empty */"
  of nnkCommentStmt:
    result.add "/// "
    result.add arg.strVal
    result.add "\n"
  of nnkIfExpr:
    var closing = ""
    for branch in arg:
      branch.matchAst:
      of nnkElifExpr(`cond`, `body`):
        result.add "("
        result.compileToGlsl(cond)
        result.add " ? "
        result.compileToGlsl(body)
        result.add " : "
        closing.add ")"
      of nnkElseExpr(`elseBody`):
        result.compileToGlsl(elseBody)
    result.add closing
  of nnkIfStmt:
    for i, branch in arg:
      if branch.kind == nnkElifBranch:
        if i == 0:
          result.add "if("
        else:
          result.add "else if("

        result.compileToGlsl(branch[0])
        result.add ") {\n"
        result.compileToGlsl(branch[1])
        result.add ";\n}"
      if branch.kind == nnkElse:
        result.add " else {\n"
        result.compileToGlsl(branch[0])
        result.add ";\n}"
      result.add "\n"
  of nnkStmtList:
    for stmt in arg:
      result.compileToGlsl(stmt)
      result.add ";\n"
  of nnkStmtListExpr( {nnkCommentStmt, nnkEmpty}, `expr`):
    result.compileToGlsl expr
  of nnkProcDef:
    let argSym = arg[0]
    argSym.expectKind nnkSym
    #for sym, code in procCache.items:
    #  if sym == argSym:
    #    result.add code
    #    return

    var code: string = ""
    code.compileProcToGlsl(arg)
    #procCache.add((argSym, code))
    result.add code
  of {nnkIdent, nnkSym}:
    var buffer = ""# buffer.setLen 0
    for c in arg.repr:
      if c != '_': # underscore is my personal separator
        buffer.add c
    result.add buffer
  of nnkDotExpr(`lhs`, `rhs`):
    # I am pretty sure this is a big hack
    let symKind = lhs.symKind
    result.compileToGlsl(lhs)
    if symKind in {nskParam, nskResult}:
      result.add '_'
    else:
      result.add '.'
    result.compileToGlsl(rhs)

  of nnkConv(`typ`, `expr`):
    result.add typ.glslType, '('
    result.compileToGlsl(expr)
    result.add ')'

  of {nnkAsgn,nnkFastAsgn}(`lhs`, `rhs`):
    result.compileToGlsl(lhs)
    result.add " = "
    result.compileToGlsl(rhs)
  of {nnkHiddenDeref, nnkHiddenAddr}(`sym`):
    result.compileToGlsl(sym)
  of nnkHiddenStdConv(nnkEmpty, `sym`):
    result.compileToGlsl(sym)
  of nnkPrefix(`op`, `arg`):
    let strVal = op.strVal
    if strVal == "-":
      result.add strVal
    elif strVal == "+":
      result.add strVal
    elif strVal == "not":
      result.add "!"
    else:
      error("unknown prefix operator: ", op)
    result.add '('
    result.compileToGlsl(arg)
    result.add ')'

  of nnkInfix(`op`, `lhs`, `rhs`):
    result.add "("
    result.compileToGlsl(lhs)
    result.add " "

    let strVal = op.strVal
    if strVal == "and":
      if arg.getTypeInst == bindSym"bool":
        result.add "&&"
      else:
        result.add "&"
    elif strVal == "or":
      if arg.getTypeInst == bindSym"bool":
        result.add "||"
      else:
        result.add "|"
    elif strVal == "mod":
      result.add "%"
    elif strVal == "shl":
      result.add "<<"
    elif strVal == "shr":
      result.add ">>"
    else:
      result.add strVal
    result.add " "
    result.compileToGlsl(rhs)
    result.add ")"
  of {nnkLetSection, nnkVarSection}:
    for memberSym, value in arg.fieldValuePairs:
      let typeStr = memberSym.getTypeInst.glslType
      result.add typeStr
      result.add ' '
      result.compileToGlsl(memberSym)
      result.add " = "
      if value.kind != nnkEmpty:
        result.compileToGlsl(value)
      else:
        result.add typeStr
        result.add "(0)"
      result.add ";\n"
    result.setLen(result.len-2)

  of nnkCall:
    arg[0].expectKind nnkSym

    let funcName = arg[0].strVal


    if funcName == "[]":
      arg.expectLen(3)
      result.compileToGlsl(arg[1])
      result.add('[')
      result.compileToGlsl(arg[2])
      result.add(']')
    elif funcName.isSwizzle:
      if funcName[^1] == '=':
        result.compileToGlsl(arg[1])
        result.add ".", funcName, " "
        result.compileToGlsl(arg[2])
      else:
        arg.expectLen(2)
        result.compileToGlsl(arg[1])
        result.add ".", funcName
    else:
      if funcName in glslConvProc:
        # TODO, mention something about this in the documentation
        result.add arg.getTypeInst.glslType
      elif funcName == "modulo":
        result.add "mod"
      else:
        result.add funcName
      result.add "("
      for arg in arg.args:
        result.compileToGlsl(arg)
        result.add ", "

      result[^2] = ')'

  of nnkBracketExpr(`syma`, `symb`):
    result.compileToGlsl(syma)
    result.add '['
    result.compileToGlsl(symb)
    result.add ']'

  of nnkReturnStmt(nnkAsgn( _, `expr`)):
    result.add "return "
    result.compileToGlsl expr

  of nnkForStmt( `loopVar` @ nnkSym, `collectionCall`, `body` ):
    var lowerBound: string
    var upperBound: string
    var loopIndexSym: NimNode
    var collectionExpr: NimNode
    collectionCall.matchAst:
    of nnkCall( ident"items", `theCollectionExpr`):
      collectionExpr = theCollectionExpr
      let collectionType = collectionExpr.getType
      collectionType.matchAst:
      of nnkBracketExpr(
        ident"array",
        nnkBracketExpr( ident"range", `a`, `b` ),
        _
      ):
        lowerBound = "0"
        upperBound = $(b.intVal - a.intVal + 1)
        loopIndexSym = genSym(nskVar, "i")
    of nnkInfix( ident"..<", `a`, `b`):
      lowerBound.compileToGlsl(a)
      upperBound.compileToGlsl(b)
      loopIndexSym = loopVar



    let irepr = loopIndexSym.repr
    result.add "for(int "
    result.add irepr
    result.add " = "
    result.add lowerBound
    result.add "; "
    result.add irepr
    result.add " < "

    result.add upperBound
    result.add "; ++"
    result.add irepr
    result.add ") {\n"

    if collectionExpr != nil:
      # TODO this is actually correct, but for now I cheat around fixing it
      # result.add loopVar.getTypeInst.glslType
      result.add loopVar.getTypeInst.strVal
      result.add ' '
      result.compileToGlsl(loopVar)
      result.add " = "
      result.compileToGlsl(collectionExpr)
      result.add "[", irepr, "];\n"
    # reintroduce nnkStmtList
    if body.kind != nnkStmtList:
      result.compileToGlsl(newStmtList(body))
    else:
      result.compileToGlsl body
    result.add "\n}"

  of nnkBlockStmt(_, `body`):
    result.add "{\n"
    result.compileToGlsl(body)
    result.add "}\n"
  of nnkWhileStmt(`cond`, `body`):
    result.add "while("
    result.compileToGlsl(cond)
    result.add ") {"
    result.compileToGlsl(body)
    result.add "}"
  of nnkCommand( ident"inc", `a`, `b`):
    result.compileToGlsl(a)
    result.add " += "
    result.compileToGlsl(b)

const AKinds = {
  nnkFloat32Lit,
  nnkFloat64Lit,
  nnkFloatLit,
  nnkInt32Lit,
  nnkInt64Lit,
  nnkIntLit,
  nnkEmpty,
  nnkCommentStmt,
  nnkIfExpr,
  nnkIfStmt,
  nnkStmtList,
  nnkStmtListExpr,
  nnkProcDef,
  nnkIdent,
  nnkSym,
  nnkDotExpr,
  nnkConv
}
