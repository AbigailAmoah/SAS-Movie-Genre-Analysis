
/* Importing dataset */
proc import datafile="C:\Users\abiga\Desktop\STA 502\PROJECT\tmdb_5000_movies.csv"
    out=movies 
    dbms=csv replace;
    getnames=yes;
run;
proc import datafile="C:\Users\abiga\Desktop\STA 502\PROJECT\tmdb_5000_credits.csv"
    out=credits 
    dbms=csv replace;
    getnames=yes;
run;

/* keep only needed variables */
data tmdb_5000_movies;
    set movies;
    keep id title genres; 
run;
data tmdb_5000_credits;
    set credits;
    keep movie_id cast crew; 
run;

/* Genre parsing for the JSON format */
data movie_genres;
    set tmdb_5000_movies;
    length genre $50;
    keep id title genre; 
    if not missing(genres) then do;
        work_string = genres;
        do while(index(work_string, '"name": "') > 0);
        		name_pos = index(work_string, '"name": "');
            if name_pos > 0 then do;
				text_start = name_pos + 9;
    /* Find the closing quote */
                text_end = index(substr(work_string, text_start), '"') + text_start - 2;
                if text_end >= text_start then do;
      /* Extract the genre name */
                    genre = substr(work_string, text_start, text_end - text_start + 1);
                    /* Output the genre */
                    if not missing(genre) then output;
                    /* Move to next potential genre */
                    work_string = substr(work_string, text_end + 2);
                end;
                else leave;
            end;
            else leave;
        end;
    end;
    drop work_string name_pos text_start text_end;
run;
/* Check the results */
proc print data=movie_genres (obs=20);
    title "Movie Genres Parsed";
run;

proc freq data=movie_genres;
    tables genre;
    title "Genre Frequencies";
run;

/* Parse cast members */
data movie_cast;
    set tmdb_5000_credits;
    length cast_member_name $100 character $200;
    keep movie_id cast_member_name character;
    
    /* Parse cast JSON */
    temp_cast = compress(cast, '[] ');
    cast_count = countw(temp_cast, '{}');
    do i = 1 to cast_count;
        cast_item = scan(temp_cast, i, '{}');
        if index(cast_item, 'name') > 0 then do;
            /* Extract cast member name */
            name_pos = index(cast_item, '"name":');
            if name_pos > 0 then do;
                name_start = name_pos + 8;
                name_end = index(substr(cast_item, name_start), '"') + name_start - 2;
                cast_member_name = substr(cast_item, name_start, name_end - name_start + 1);
                /* Extract character */
                char_pos = index(cast_item, '"character":');
                if char_pos > 0 then do;
                    char_start = char_pos + 13;
                    char_end = index(substr(cast_item, char_start), '"') + char_start - 2;
                    character = substr(cast_item, char_start, char_end - char_start + 1);
                end;
                
                output;
            end;
        end;
    end;
    drop temp_cast cast_count i cast_item name_pos name_start name_end char_pos char_start char_end;
run;

/* Parse crew members */
data movie_crew;
    set tmdb_5000_credits;
    length crew_member_name $100 job $50;
    keep movie_id crew_member_name job;
    temp_crew = compress(crew, '[] ');
    crew_count = countw(temp_crew, '{}');
    do i = 1 to crew_count;
        crew_item = scan(temp_crew, i, '{}');
        if index(crew_item, 'name') > 0 then do;
            /* Extract crew member name */
            name_pos = index(crew_item, '"name":');
            job_pos = index(crew_item, '"job":');
            
            if name_pos > 0 and job_pos > 0 then do;
                /* Extract name */
                name_start = name_pos + 8;
                name_end = index(substr(crew_item, name_start), '"') + name_start - 2;
                crew_member_name = substr(crew_item, name_start, name_end - name_start + 1);
                
                /* Extract job */
                job_start = job_pos + 7;
                job_end = index(substr(crew_item, job_start), '"') + job_start - 2;
                job = substr(crew_item, job_start, job_end - job_start + 1);
                
                /* Keep only producers and directors */
                if upcase(job) in ('PRODUCER', 'EXECUTIVE PRODUCER', 'DIRECTOR') then output;
            end;
        end;
    end;
    drop temp_crew crew_count i crew_item name_pos name_start name_end job_pos job_start job_end;
run;

/* Find movies where producers/directors also appear in cast */
proc sql;
    create table overlap_movies as
    select distinct 
        c.movie_id,
        c.crew_member_name as person_name,
        c.job,
        ca.character
    from movie_crew c
    inner join movie_cast ca on c.movie_id = ca.movie_id 
                            and c.crew_member_name = ca.cast_member_name;
quit;

/* Frequency analysis */
proc sql;
    create table genre_overlap_stats as
    select 
        mg.genre,
        count(distinct mg.id) as total_movies_in_genre,
        count(distinct case when om.movie_id is not null then mg.id end) as movies_with_overlap,
        calculated movies_with_overlap / calculated total_movies_in_genre as relative_frequency
    from movie_genres mg
    left join overlap_movies om on mg.id = om.movie_id
    group by mg.genre
    order by relative_frequency desc;
quit;
/*rtf output*/
ods rtf file="C:\Users\abiga\Desktop\STA 502\PROJECT\movie frequency.rtf";

proc print data=genre_overlap_stats noobs;
    title "Relative Frequency of Producer/Director Cast Overlap by Genre";
    var genre total_movies_in_genre movies_with_overlap relative_frequency;
    format relative_frequency percent8.2;
run;

/* Bar chart */
proc sgplot data=genre_overlap_stats;
    where relative_frequency > 0.10; 
    vbar genre / response=relative_frequency;
    yaxis label="Relative Frequency" valuesformat=percent8.0;
    title "Producer/Director Cast Overlap by Genre";
    xaxis display=(nolabel) fitpolicy=rotate;
run;
ods rtf close;

/*Creating the macro*/

%macro AbiMacro(genres);
    /* Process specified genres */
    data selected_genres;
        set movie_genres;
        where upcase(genre) in (%upcase(&genres));
    run;
    
    proc sql;
        create table results as
        select 
            sg.genre,
            count(distinct sg.id) as total_movies,
            count(distinct case when om.movie_id is not null then sg.id end) as overlap_movies,
            calculated overlap_movies / calculated total_movies as relative_frequency format=percent8.2
        from selected_genres sg
        left join overlap_movies om on sg.id = om.movie_id
        group by sg.genre
        order by relative_frequency desc;
    quit;
    
    /* Display results */
    title "Relative Frequency of Producer/Director Cast Overlap";
    proc print data=results noobs;
        var genre total_movies overlap_movies relative_frequency;
    run;
    title;
%mend AbiMacro;

/* Testing the Macro*/

%AbiMacro('Action');

%AbiMacro(%str('Animation','Documentary'));

%analyze_genre_overlap(%str('action','Comedy','Drama'));
