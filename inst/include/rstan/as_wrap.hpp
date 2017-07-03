#include <RcppCommon.h>

#include <stan/math.hpp>

namespace Rcpp {

  namespace traits {
    SEXP wrap(const stan::math::var & obj);
    template <> class Exporter< stan::math::var >;
  }
}

#include <Rcpp.h>

namespace Rcpp {

  namespace traits {
  
    SEXP wrap(const stan::math::var & obj) {
      Rcomplex x;
      x.r = obj.val();
      x.i = obj.adj();
      Rcpp::ComplexVector out = Rcpp::ComplexVector::create(x);
      std::cout << "out = " << out << std::endl;
      return Rcpp::NumericVector::create(obj.val(), obj.adj());
    };
  
    template <> class Exporter< stan::math::var > {
      stan::math::var x_var;
      public:
        Exporter(SEXP x) : x_var(Rcpp::as<double>(x)) {
        }
        stan::math::var get() {
          return x_var;
        }
      };
  }
}
