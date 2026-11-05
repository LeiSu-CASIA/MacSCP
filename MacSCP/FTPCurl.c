#include <curl/curl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <limits.h>

typedef size_t (*macscp_ftp_write_fn)(const unsigned char *, size_t, void *);
typedef int (*macscp_ftp_progress_fn)(int64_t,int64_t,int64_t,int64_t,void *);
static pthread_once_t ftp_once=PTHREAD_ONCE_INIT;
static void ftp_init(void){curl_global_init(CURL_GLOBAL_DEFAULT);}
void *macscp_ftp_new(void){pthread_once(&ftp_once,ftp_init);return curl_easy_init();}
void macscp_ftp_free(void *handle){if(handle)curl_easy_cleanup((CURL *)handle);}
const char *macscp_ftp_error(int code){return curl_easy_strerror((CURLcode)code);}
struct ftp_callbacks{macscp_ftp_write_fn write;macscp_ftp_progress_fn progress;void *user;FILE *upload;curl_off_t remaining,total;};
static size_t ftp_discard(char *bytes,size_t size,size_t count,void *opaque){(void)bytes;(void)opaque;return size && count>SIZE_MAX/size ? 0 : size*count;}
static size_t ftp_write(char *bytes,size_t size,size_t count,void *opaque){struct ftp_callbacks *cb=opaque;if(size && count>SIZE_MAX/size)return 0;return cb->write((const unsigned char *)bytes,size*count,cb->user);}
static int ftp_progress(void *opaque,curl_off_t dt,curl_off_t dn,curl_off_t ut,curl_off_t un){struct ftp_callbacks *cb=opaque;return cb->progress((int64_t)dt,(int64_t)dn,(int64_t)ut,(int64_t)un,cb->user);}
static int ftp_seek(void *opaque,curl_off_t offset,int origin){struct ftp_callbacks *cb=opaque;if(origin!=SEEK_SET||offset<0||offset>cb->total)return CURL_SEEKFUNC_FAIL;if(fseeko(cb->upload,(off_t)offset,SEEK_SET))return CURL_SEEKFUNC_FAIL;cb->remaining=cb->total-offset;return CURL_SEEKFUNC_OK;}
static size_t ftp_read(char *bytes,size_t size,size_t count,void *opaque){struct ftp_callbacks *cb=opaque;if(size && count>SIZE_MAX/size)return CURL_READFUNC_ABORT;size_t maximum=size*count;if((curl_off_t)maximum>cb->remaining)maximum=(size_t)cb->remaining;if(!maximum)return 0;size_t n=fread(bytes,1,maximum,cb->upload);if(!n && (ferror(cb->upload)||cb->remaining))return CURL_READFUNC_ABORT;cb->remaining-=(curl_off_t)n;return n;}
// 0 RETR, 1 MLSD, 2 LIST, 3 login/PWD metadata, 4 STOR temporary content, 5 typed quote commands.
int macscp_ftp_request(void *handle,const char *url,const char *user,const char *password,int tls,int timeout,int ssl_auth_first,int operation,int64_t offset,int source_fd,const char *upload,const char *commands,const char *ca_file,void *opaque,macscp_ftp_write_fn write,macscp_ftp_progress_fn progress,long *reply,const char **entry,int64_t *length,int64_t *modified){
 CURL *c=handle;struct curl_slist *quotes=NULL;char *copy=NULL;FILE *file=NULL;struct stat original={0},after={0};int result=CURLE_OK;struct ftp_callbacks cb={write,progress,opaque,NULL,0,0};
 if(!c)return CURLE_FAILED_INIT;
 curl_easy_reset(c);
#define SET(option,value) do{CURLcode e=curl_easy_setopt(c,option,value);if(e!=CURLE_OK){result=(int)e;goto done;}}while(0)
 SET(CURLOPT_URL,url);SET(CURLOPT_USERNAME,user);SET(CURLOPT_PASSWORD,password);
 SET(CURLOPT_PROXY,"");SET(CURLOPT_NETRC,(long)CURL_NETRC_IGNORED);SET(CURLOPT_FOLLOWLOCATION,0L);
 SET(CURLOPT_PROTOCOLS_STR,"ftp,ftps");SET(CURLOPT_REDIR_PROTOCOLS_STR,"ftp,ftps");
 SET(CURLOPT_SSL_VERIFYPEER,1L);SET(CURLOPT_SSL_VERIFYHOST,2L);SET(CURLOPT_SSLVERSION,(long)CURL_SSLVERSION_TLSv1_2);
 if(tls){SET(CURLOPT_USE_SSL,(long)CURLUSESSL_ALL);SET(CURLOPT_FTPSSLAUTH,(long)(ssl_auth_first ? CURLFTPAUTH_SSL : CURLFTPAUTH_TLS));}
 if(ca_file && *ca_file)SET(CURLOPT_CAINFO,ca_file);
 SET(CURLOPT_FTP_SKIP_PASV_IP,1L);SET(CURLOPT_FTP_USE_EPSV,1L);SET(CURLOPT_NOSIGNAL,1L);SET(CURLOPT_CONNECTTIMEOUT,(long)timeout);SET(CURLOPT_FTP_RESPONSE_TIMEOUT,(long)timeout);
 SET(CURLOPT_LOW_SPEED_LIMIT,1L);SET(CURLOPT_LOW_SPEED_TIME,120L);
 SET(CURLOPT_WRITEFUNCTION,ftp_write);SET(CURLOPT_WRITEDATA,&cb);SET(CURLOPT_NOPROGRESS,0L);SET(CURLOPT_XFERINFOFUNCTION,ftp_progress);SET(CURLOPT_XFERINFODATA,&cb);
 if(operation==1)SET(CURLOPT_CUSTOMREQUEST,"MLSD");
 if(operation==2)SET(CURLOPT_CUSTOMREQUEST,"LIST");
 if((operation==7 || operation==8) && offset<0){result=CURLE_BAD_FUNCTION_ARGUMENT;goto done;}
 if((operation==7 || operation==8) && offset>0)SET(CURLOPT_RESUME_FROM_LARGE,(curl_off_t)offset);
 if(operation==6)SET(CURLOPT_FILETIME,1L);
 if(operation==3 || operation==5 || operation==6)SET(CURLOPT_NOBODY,1L);
 if(operation==4 || operation==8){
  int fd=source_fd>=0 ? dup(source_fd) : open(upload,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);if(fd<0){result=CURLE_READ_ERROR;goto done;}
  if(fstat(fd,&original)||!S_ISREG(original.st_mode)||original.st_size<0){close(fd);result=CURLE_READ_ERROR;goto done;}
  file=fdopen(fd,"rb");if(!file){close(fd);result=CURLE_READ_ERROR;goto done;}
  if(fseeko(file,0,SEEK_SET)){result=CURLE_READ_ERROR;goto done;}
  cb.upload=file;cb.remaining=cb.total=(curl_off_t)original.st_size;SET(CURLOPT_SEEKFUNCTION,ftp_seek);SET(CURLOPT_SEEKDATA,&cb);SET(CURLOPT_UPLOAD,1L);SET(CURLOPT_READFUNCTION,ftp_read);SET(CURLOPT_READDATA,&cb);SET(CURLOPT_INFILESIZE_LARGE,(curl_off_t)original.st_size);
 }
 if(commands && *commands){copy=strdup(commands);if(!copy){result=CURLE_OUT_OF_MEMORY;goto done;}char *cursor=NULL,*line=strtok_r(copy,"\n",&cursor);while(line){struct curl_slist *next=curl_slist_append(quotes,line);if(!next){result=CURLE_OUT_OF_MEMORY;goto done;}quotes=next;line=strtok_r(NULL,"\n",&cursor);}SET(CURLOPT_QUOTE,quotes);}
 result=(int)curl_easy_perform(c);
 if(file && (fstat(fileno(file),&after)||after.st_size!=original.st_size||after.st_mtime!=original.st_mtime||after.st_mtimespec.tv_nsec!=original.st_mtimespec.tv_nsec||cb.remaining!=0) && result==CURLE_OK)result=CURLE_READ_ERROR;
 done:
 if(reply)curl_easy_getinfo(c,CURLINFO_RESPONSE_CODE,reply);
 if(entry)curl_easy_getinfo(c,CURLINFO_FTP_ENTRY_PATH,entry);
 if(length){curl_off_t n=-1;curl_easy_getinfo(c,CURLINFO_CONTENT_LENGTH_DOWNLOAD_T,&n);*length=(int64_t)n;}
 if(modified){curl_off_t n=-1;curl_easy_getinfo(c,CURLINFO_FILETIME_T,&n);*modified=(int64_t)n;}
 if(file)fclose(file);curl_slist_free_all(quotes);free(copy);
 // Reset borrowed callback pointers before their Swift owners leave scope; keep connection cache.
 curl_easy_setopt(c,CURLOPT_QUOTE,NULL);curl_easy_setopt(c,CURLOPT_WRITEFUNCTION,ftp_discard);curl_easy_setopt(c,CURLOPT_WRITEDATA,NULL);curl_easy_setopt(c,CURLOPT_NOPROGRESS,1L);curl_easy_setopt(c,CURLOPT_XFERINFOFUNCTION,NULL);curl_easy_setopt(c,CURLOPT_XFERINFODATA,NULL);curl_easy_setopt(c,CURLOPT_READDATA,NULL);curl_easy_setopt(c,CURLOPT_READFUNCTION,NULL);curl_easy_setopt(c,CURLOPT_SEEKFUNCTION,NULL);curl_easy_setopt(c,CURLOPT_SEEKDATA,NULL);
 return result;
#undef SET
}
