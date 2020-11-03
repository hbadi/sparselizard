// sparselizard - Copyright (C) see copyright file.
//
// See the LICENSE file for license information. Please report all
// bugs and problems to <alexandre.halbach at gmail.com>.


#ifndef OPPARAMETER_H
#define OPPARAMETER_H

#include "operation.h"
#include "rawparameter.h"

class rawparameter;

class opparameter: public operation
{

    private:
        
        bool reuse = false;
        
        int myrow;
        int mycolumn;
        
        std::shared_ptr<rawparameter> myparameter;
    
    public:
        
        opparameter(std::shared_ptr<rawparameter> input, int row, int col) { myparameter = input; myrow = row; mycolumn = col; };
        
        std::vector<std::vector<densematrix>> interpolate(elementselector& elemselect, std::vector<double>& evaluationcoordinates, expression* meshdeform);
        densematrix multiharmonicinterpolate(int numtimeevals, elementselector& elemselect, std::vector<double>& evaluationcoordinates, expression* meshdeform);
        
        std::shared_ptr<rawparameter> getparameterpointer(void) { return myparameter; };
        
        bool isharmonicone(std::vector<int> disjregs);
        
        std::shared_ptr<operation> simplify(std::vector<int> disjregs);
        bool isvalueorientationdependent(std::vector<int> disjregs);
        
        std::shared_ptr<operation> copy(void);
        
        void reuseit(bool istobereused) { reuse = istobereused; };
        
        void print(void);

};

#endif
