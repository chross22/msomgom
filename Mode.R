Mode <- function(x, na.rm = FALSE) {
#http://stackoverflow.com/questions/2547402/is-there-a-built-in-function-for-finding-the-mode  
  if(na.rm){
    x = x[!is.na(x)]
  }
  
  ux <- unique(x)
  return(ux[which.max(tabulate(match(x, ux)))])
}