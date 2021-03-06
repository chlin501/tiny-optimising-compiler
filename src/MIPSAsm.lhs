\begin{code}
{-# LANGUAGE DeriveAnyClass #-}
module MIPSAsm(generateASM, ASMDoc(..)) where
import qualified OrderedMap as M
import Control.Monad.State.Strict
import Data.Traversable
import Data.Foldable
import Control.Applicative
import qualified Data.List.NonEmpty as NE
import IR
import Data.Text.Prettyprint.Doc as PP
import PrettyUtils

-- This module assumes that constants in all parameters are canonicalized
-- to be the second parameter.

-- | Parameter to MIPS Instructions
type MIPSParam = Doc ()

-- | Instruction Name
type MIPSInstName = Doc ()

-- | a Mips instruction
type MIPSInst = Doc ()

-- | a mips register name
type MIPSRegName = Doc ()

-- | a mips label
type MIPSLabel = Doc ()

data ASMContext = ASMContext {
    instToReg :: M.OrderedMap (Label Inst) MIPSRegName,
    insts :: [MIPSInst],
    irprogram :: IRProgram
}

initASMContext :: IRProgram -> ASMContext
initASMContext program = ASMContext {
  instToReg=mempty,
  insts=mempty,
  irprogram=program
}



newtype ASMDoc = ASMDoc { unASMDoc :: Doc () }

-- | The zero register
zeroReg :: MIPSRegName
zeroReg = pretty "$zero"

-- | Compile an instruction that sets a particular register value
compileSetRegisterValue :: MIPSRegName  -> MIPSParam -> State ASMContext ()
compileSetRegisterValue regname param =
    appendMIPSInst $ pretty "ori" <+> regname <+> zeroReg <+> param



-- | append a MIPSInst to the ASMContext
appendMIPSInst :: MIPSInst -> State ASMContext ()
appendMIPSInst mi = modify (\ctx -> ctx {insts=(insts ctx) ++ [mi]})

-- | Compile binary operator
compileBinaryOp :: MIPSInstName ->  Value -> Value -> State ASMContext ()
compileBinaryOp name v1 v2 = do
    p1 <- compileValue v1
    p2 <- compileValue v2
    appendMIPSInst $ name <+> p1 <+> p2

-- | Compile Instruction.
appendInst :: Named Inst -> State ASMContext ()
appendInst Named {namedData=InstAlloc} = error "alloc should not be present in SSA"
appendInst Named {namedData=inst@(InstStore _ _)} = error . docToString $
    pretty inst <+> pretty "should not be present in SSA"
appendInst Named {namedData=inst@(InstLoad _)} = error . docToString $
    pretty inst <+> pretty "should not be present in SSA"

-- | compile a ret inst
appendRetInst :: RetInst -> State ASMContext ()
appendRetInst (RetInstRet val) = do
    param <- compileValue val
    -- | 1 is the ID of print_int
    compileSetRegisterValue (pretty "$v0") (pretty (1 :: Int))
    compileSetRegisterValue (pretty "$a0") param
    appendMIPSInst $ pretty "syscall"

    -- | 10 is the ID of terminate
    compileSetRegisterValue (pretty "$v0") (pretty (10 :: Int))
    appendMIPSInst $ pretty "syscall"

appendRetInst (RetInstBranch lbl) = do
    mipslabel <- compileBBLabel lbl
    appendMIPSInst $ pretty "j" <+> mipslabel


appendRetInst (RetInstConditionalBranch cond tlabel flabel) = do
    tmipslabel <- compileBBLabel tlabel
    fmipslabel <- compileBBLabel flabel
    condparam <- compileValue cond
    -- | if cond != 0, goto true
    appendMIPSInst $ pretty "bne" <+> condparam <+> zeroReg <+> tmipslabel
    appendMIPSInst $ pretty "j" <+> fmipslabel

-- | Construct a `Param` from `Value
compileValueRaw_ :: ASMContext -> Value -> MIPSParam
compileValueRaw_ _(ValueConstInt i) = pretty i
compileValueRaw_ ctx (ValueInstRef name) =
    case M.lookup name  (instToReg ctx) of
        Just param -> param
        Nothing -> error . docToString $ pretty name <+> pretty "not in instToReg"

-- | State version of `compileValueRaw_`
compileValue :: Value -> State ASMContext MIPSParam
compileValue value = gets (\ctx -> compileValueRaw_ ctx value)

entryBBLabel :: State ASMContext (Label BasicBlock)
entryBBLabel =
    gets (\ctx -> let
                    program :: IRProgram
                    program = irprogram ctx

                    entrybbid :: BBId
                    entrybbid = irProgramEntryBBId program

                    entrybb :: BasicBlock
                    entrybb = (irProgramBBMap program) M.! entrybbid
                  in bbLabel entrybb)

-- | convert a BB label to a MIPSLabel
compileBBLabel :: Label BasicBlock -> State ASMContext (MIPSLabel)
compileBBLabel label = do
    entrylabel <- entryBBLabel
    -- | Rename entry label to `main`
    let label' = if entrylabel == label then (Label "main") else label
    return . pretty . unLabel $ label'

-- | Append a basic block label into the assembly.
appendBBLabel :: Label BasicBlock -> State ASMContext ()
appendBBLabel lbl = do
    mipslbl <- compileBBLabel lbl
    appendMIPSInst $ mipslbl <+> pretty ":"

-- | Compile a Basic Block
compileBB :: BasicBlock -> State ASMContext ()
compileBB bb = do
    appendBBLabel (bbLabel bb)
    for (bbInsts bb) appendInst
    appendRetInst (bbRetInst bb)

-- | Generate ASM
generateASM :: IRProgram -> ASMDoc
generateASM program =
  ASMDoc $ vcat $ insts $ execState (do
    -- | Compile all basic blocks
    for (M.elems (irProgramBBMap program)) compileBB) (initASMContext program)
\end{code}
