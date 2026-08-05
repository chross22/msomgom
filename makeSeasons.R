makeSeasons <- function(begYEAR,endYEAR,ssn_beg,ssn_end){
  ## INPUTS
    #BEGINNING AND ENDING YEAR
    # begYEAR=2000
    # endYEAR=2001
  
    #BEGINNING AND ENDING OF SEASONS
    # ssn_beg=rbind(c(8,1), c(9,1))
    # ssn_end=rbind(c(8,31),c(9,30))
    # season_ID='MONTHLY' #IDENTIFIER TO BE USED FOR NAMING, AND WHICH IS UNIQUE TO SEASON BOUNDARIES
  
  uy=begYEAR:endYEAR
  num_ssn=dim(ssn_beg)[1] #NUMBER OF SEASONS
  
  season = matrix(data = NA, nrow = (length(uy)*num_ssn), ncol = 9)
  season = as.data.frame(season)
  names(season) = c("Y","M_BEG","D_BEG","M_END","D_END","JDAY_BEG","JDAY_END","SSN_NO","SSN_GRPD_NO")
  ctr=1
  for (i in 1:length(uy)){  
    for (j in 1:num_ssn){   
      
      season[ctr,1] = uy[i] #column 1: year
      
      season[ctr,2] = ssn_beg[j,1] #column 2: month of beginning of season
      season[ctr,3] = ssn_beg[j,2] #column 3: day of beginning of season
      season[ctr,4]=ssn_end[j,1] #column 4: month of end of season
      season[ctr,5]=ssn_end[j,2] #column 5: day of end of season
      season[ctr,8]=ctr #absolute season number
      season[ctr,9]=j #season number grouped within year
      
      ctr=ctr+1; #advance the counter
    }
  }
  
  #insert yearday for beginning and end of seasons into columns 6 and 7, respectively
  season[,6] <- as.numeric(format(as.Date(paste(season[,1],season[,2],season[,3],sep="-"),"%Y-%m-%d"), "%j"))
  season[,7] <- as.numeric(format(as.Date(paste(season[,1],season[,4],season[,5],sep="-"),"%Y-%m-%d"), "%j"))

  return(season)
}
