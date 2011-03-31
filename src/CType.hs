module CType where

data CTypes = CTString | CTInt | CTDouble | CTBool | CTDoubleStar

data CPPTypes = CPTClass String 

data IsConst = Const | NoConst

data Types = Void 
           | SelfType
           | CT  CTypes IsConst 
           | CPT CPPTypes IsConst

self_ :: Types 
self_ = SelfType

cstring_ :: Types
cstring_ = CT CTString Const 

cint_ :: Types
cint_    = CT CTInt    Const

int_ :: Types 
int_     = CT CTInt    NoConst

cdouble_ :: Types
cdouble_ = CT CTDouble Const

double_ :: Types
double_  = CT CTDouble NoConst

doublep_ :: Types
doublep_ = CT CTDoubleStar NoConst

bool_ :: Types 
bool_    = CT CTBool   NoConst 

void_ :: Types
void_ = Void 

cstring :: String -> (Types,String)
cstring var = (cstring_ , var)

cint :: String -> (Types,String)
cint    var = (cint_    , var) 

int :: String -> (Types,String)
int     var = (int_     , var)

cdouble :: String -> (Types,String)
cdouble var = (cdouble_ , var)

double :: String -> (Types,String)
double  var = (double_  , var)

doublep :: String -> (Types,String)
doublep var = (doublep_ , var)

bool :: String -> (Types,String)
bool    var = (bool_    , var)

cppclass :: String -> Types
cppclass name =  CPT (CPTClass name) NoConst

hsCTypeName :: CTypes -> String 
hsCTypeName CTString = "CString" 
hsCTypeName CTInt    = "CInt"
hsCTypeName CTDouble = "CDouble"
hsCTypeName CTDoubleStar = "(Ptr CDouble)"
hsCTypeName CTBool   = "CInt"

hsCppTypeName :: CPPTypes -> String
hsCppTypeName (CPTClass name) =  "(Ptr Raw"++name++")"  

