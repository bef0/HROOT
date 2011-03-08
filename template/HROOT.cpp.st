#include <iostream>

#include "$headerfilename$"

#include "TMath.h"
#include "TFile.h"
#include "TStyle.h"
#include "TLatex.h"
#include "TTree.h"
#include "TChain.h"
#include "TH1F.h"
#include "TH2F.h"
#include "THStack.h"

#include "TNamed.h"
#include "TAttLine.h"
#include "TAttAxis.h"

#include "TCanvas.h"
#include "TGraph.h"
#include "TLorentzVector.h"
#include "TStyle.h" 
#include "TF1.h"
#include "TAxis.h"

#include "TLine.h"

using namespace std;


template<class ToType, class FromType>
const ToType* to_const(const FromType* x) {
  return reinterpret_cast<const ToType*>(x);
}

template<class ToType, class FromType>
ToType* to_nonconst(FromType* x) {
  return reinterpret_cast<ToType*>(x);
}



$cppbody$