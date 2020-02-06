void /*unique*/unique(void);

#if defined(THIS_IS_FROM_C)
#warning UNIQUE_INCLUDED_FROM_C
#elif defined(THIS_IS_FROM_D)
#warning UNIQUE_INCLUDED_FROM_D
#else
#warning UNKNOWN_MAIN_FILE
#endif
