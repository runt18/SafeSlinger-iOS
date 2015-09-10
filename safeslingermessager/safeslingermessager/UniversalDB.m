/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2010-2015 Carnegie Mellon University
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "UniversalDB.h"
#import "ErrorLogger.h"
#import "SafeSlingerDB.h"
#import "Utility.h"
#import "SSEngine.h"
#import "Config.h"

@implementation UniversalDB

// private method
- (BOOL) LoadDBFromStorage
{
    BOOL success = YES;
	@try{
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSError *error;
        NSString *db_path = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent: @"universal.db"];
        
        if (![fileManager fileExistsAtPath:db_path])
        {
            // The writable database does not exist, so copy the default to the appropriate location.
            NSString *defaultDBPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"universal.db"];
            if (![fileManager copyItemAtPath:defaultDBPath toPath:db_path error:&error])
            {
                [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: Failed to create writable database file with message '%@'.", [error localizedDescription]]];
                success = NO;
            }
        }
        
        if(!(sqlite3_open([db_path UTF8String], &db) == SQLITE_OK)){
            [ErrorLogger ERRORDEBUG:@"ERROR: Unable to open database."];
            success = NO;
        }
        
    }@catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: An exception occured, %@", [exception reason]]];
        success = NO;
    }@finally {
        return success;
    }
}

- (BOOL)CheckMessage: (NSData*)msgid
{
    if(!db || !msgid){
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
        return NO;
    }
    
    BOOL exist = NO;
    
    sqlite3_stmt *sqlStatement = NULL;
    const char *sql = "SELECT COUNT(*) FROM ciphertable WHERE msgid=?";
        
    if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) == SQLITE_OK){
        // bind msgid
        sqlite3_bind_blob(sqlStatement, 1, [msgid bytes], (int)[msgid length], SQLITE_TRANSIENT);
        if(sqlite3_step(sqlStatement) == SQLITE_OK)
        {
            if(sqlite3_column_int(sqlStatement, 0)>0)
                exist = YES;
        }
        sqlite3_finalize(sqlStatement);
    }
    
    return exist;
}

- (BOOL)createNewEntry:(MsgEntry *)msg {
    
    if(!db || !msg){
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
        return NO;
    }
    
    BOOL ret = NO;
    sqlite3_stmt *sqlStatement = NULL;
    const char *sql = "insert into ciphertable (msgid, cTime, keyid, cipher) Values (?,?,?,?);";
    
    if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) == SQLITE_OK){
        const NSString* unknownFlag = @"UNDEFINED";
        // msgid
        sqlite3_bind_blob(sqlStatement, 1, [msg.msgid bytes], (int)[msg.msgid length], SQLITE_TRANSIENT);
        // time
        sqlite3_bind_text(sqlStatement, 2, [msg.cTime UTF8String], -1, SQLITE_TRANSIENT);
        // unknown for keyid
        sqlite3_bind_text(sqlStatement, 3, [unknownFlag UTF8String], -1, SQLITE_TRANSIENT);
        // empty for cipher
        sqlite3_bind_null(sqlStatement, 4);
        int error = sqlite3_step(sqlStatement);
        if(error == SQLITE_DONE)
            ret = YES;
        else
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat: @"ERROR: Error while inserting data. '%s'", sqlite3_errstr(error)]];
        sqlite3_finalize(sqlStatement);
    }
        
    return ret;
}

- (BOOL)updateMessageEntry:(MsgEntry *)msg {
	
    if(!db || !msg)
    {
		[ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
		return NO;
	}
	
	BOOL ret = NO;
	
    // update entry
    sqlite3_stmt *sqlStatement = NULL;
    const char *sql = "UPDATE ciphertable SET keyid=?, cipher=? WHERE msgid=?";
    if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) == SQLITE_OK){
        sqlite3_bind_text(sqlStatement, 1, [msg.keyid UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_blob(sqlStatement, 2, [msg.msgbody bytes], (int)[msg.msgbody length], SQLITE_TRANSIENT);
        sqlite3_bind_blob(sqlStatement, 3, [msg.msgid bytes], (int)[msg.msgid length], SQLITE_TRANSIENT);
        int error = sqlite3_step(sqlStatement);
        if(error == SQLITE_DONE)
            ret = YES;
        else
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat: @"Error while updating data. '%s'", sqlite3_errstr(error)]];
        sqlite3_finalize(sqlStatement);
    }
    return ret;
}

- (NSArray*)GetEntriesForKeyID: (NSString*)keyid WithToken:(NSString*)token WithName:(NSString*)name
{
    if(!db || !keyid || !token || !name)
    {
        [ErrorLogger ERRORDEBUG:@"ERROR: DB Object is null or input is null."];
        return nil;
    }
	
    NSMutableArray *Ciphers = nil;
    @try {
        
        Ciphers = [NSMutableArray arrayWithCapacity:0];
        const char *sql = NULL;
        sqlite3_stmt *sqlStatement;
        
        sql = "SELECT * FROM ciphertable WHERE keyid=?;";
        if(sqlite3_prepare(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK)
        {
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: Problem with prepare statement: %s", sql]];
            Ciphers = nil;
        }
        
        sqlite3_bind_text(sqlStatement, 1, [keyid UTF8String], -1, SQLITE_TRANSIENT);
        
        while (sqlite3_step(sqlStatement)==SQLITE_ROW) {
            
            NSData *nonce = [NSData dataWithBytes:sqlite3_column_blob(sqlStatement, 0) length:sqlite3_column_bytes(sqlStatement, 0)];
            NSData *cipher = [NSData dataWithBytes:sqlite3_column_blob(sqlStatement, 3) length:sqlite3_column_bytes(sqlStatement, 3)];
            
            MsgEntry* newmsg = [[MsgEntry alloc]InitIncomingMessage:nonce UserName:name Token:token Message:cipher SecureM:Encrypted SecureF:Decrypted];
            
            newmsg.rTime = newmsg.cTime = [NSString stringWithUTF8String:(char*)sqlite3_column_text(sqlStatement, 1)];
            [Ciphers addObject:newmsg];
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"An exception occured: %@", [exception reason]]];
        Ciphers = nil;
    }
    @finally {
        return Ciphers;
    }
}

- (int)updateThreadEntries:(NSMutableArray *)threadlist {
    
    if(!db || !threadlist) {
        [ErrorLogger ERRORDEBUG:@"ERROR: DB Object is null or input is null."];
        return -1;
    }
    
    int NumMessage = 0;
    
    sqlite3_stmt *sqlStatement = NULL;
    const char *sql = "SELECT keyid, cTime, count(msgid) FROM ciphertable GROUP BY keyid order by cTime desc;";
		
    if(sqlite3_prepare(db, sql, -1, &sqlStatement, NULL) == SQLITE_OK) {
        
        while (sqlite3_step(sqlStatement) == SQLITE_ROW) {
            
            NSString* keyid = [NSString stringWithUTF8String:(char*)sqlite3_column_text(sqlStatement, 0)];
            DEBUGMSG(@"keyid = %@", keyid);
            
            MsgListEntry *listEntry;
            
            for(int i = 0; i < threadlist.count; i++) {
                if([keyid isEqualToString:((MsgListEntry *)threadlist[i]).keyid]) {
                    listEntry = threadlist[i];
                    break;
                }
            }
            
            if(listEntry) {
                // update information
                DEBUGMSG(@"modify entry thread.");
                NSString *date1 = [NSString stringWithUTF8String:(char*)sqlite3_column_text(sqlStatement, 1)];
                // compare dates
                if ([UtilityFunc CompareDate:date1 Target:listEntry.lastSeen] == NSOrderedDescending) {
                    listEntry.lastSeen = date1;
                    [threadlist removeObject:listEntry];
                    [self insertMessageListEntry:listEntry orderedByDateDescendingInArray:threadlist];
                }
                listEntry.ciphercount = sqlite3_column_int(sqlStatement, 2);
                NumMessage += listEntry.ciphercount;
                listEntry.messagecount += listEntry.ciphercount;
            } else {
                // create entry
                DEBUGMSG(@"create new entry thread.");
                listEntry = [[MsgListEntry alloc]init];
                listEntry.keyid = keyid;
                listEntry.lastSeen = [NSString stringWithUTF8String:(char*)sqlite3_column_text(sqlStatement, 1)];
                listEntry.messagecount = listEntry.ciphercount = sqlite3_column_int(sqlStatement, 2);
                NumMessage += listEntry.ciphercount;
                [self insertMessageListEntry:listEntry orderedByDateDescendingInArray:threadlist];
            }
        } // end of while
    }
        
    sqlite3_finalize(sqlStatement);
    return NumMessage;
}

- (void)insertMessageListEntry:(MsgListEntry *)listEntry orderedByDateDescendingInArray:(NSMutableArray *)threadList {
	int index = 0;
	BOOL inserted = false;
	
	while(index < threadList.count && !inserted) {
		MsgListEntry *entry = threadList[index];
		if([UtilityFunc CompareDate:listEntry.lastSeen Target:entry.lastSeen] == NSOrderedDescending) {
			[threadList insertObject:listEntry atIndex:index];
			inserted = true;
		}
		index++;
	}
	
	if(!inserted) {
		// if date is smaller than any other thread, insert at the end
		[threadList addObject:listEntry];
	}
}

- (int)ThreadCipherCount: (NSString*)KEYID
{
    if(!db || !KEYID)
    {
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
        return 0;
    }
    
    int count = 0;
    const char *sql = "SELECT count(msgid) FROM ciphertable WHERE keyid=?";
    sqlite3_stmt *sqlStatement = NULL;
    if(sqlite3_prepare(db, sql, -1, &sqlStatement, NULL) == SQLITE_OK)
    {
        sqlite3_bind_text(sqlStatement, 1, [KEYID UTF8String], -1, SQLITE_TRANSIENT);
        int error = sqlite3_step(sqlStatement);
        if(error==SQLITE_OK)
        {
            count = sqlite3_column_int(sqlStatement, 0);
        }else{
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"Error while querying data. '%s'", sqlite3_errstr(error)]];
        }
        sqlite3_finalize(sqlStatement);
    }
    return count;
}

- (BOOL)DeleteMessage: (NSData*)msgid
{
    if(!db || !msgid){
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
        return NO;
    }
    
    BOOL ret = YES;
    sqlite3_stmt *sqlStatement;
    const char *sql = "DELETE FROM ciphertable WHERE msgid=?";
        
    if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) == SQLITE_OK){
        // bind msgid
        sqlite3_bind_blob(sqlStatement, 1, [msgid bytes], (int)[msgid length], SQLITE_TRANSIENT);
        int error = sqlite3_step(sqlStatement);
        if(error != SQLITE_DONE){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat:@"Error while deleting data. '%s'", sqlite3_errstr(error)]];
            ret = NO;
        }
        sqlite3_finalize(sqlStatement);
    }
    
    return ret;
}

- (NSArray*)LoadThreadMessage: (NSString*)KEYID
{
    if(!db || !KEYID)
    {
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
        return nil;
    }
    
    NSMutableArray *tmparray = nil;
    
    int rownum = 0;
    tmparray = [NSMutableArray arrayWithCapacity:0];
    
    const char *sql = "SELECT * FROM ciphertable WHERE keyid=? ORDER BY cTime ASC";
    sqlite3_stmt *sqlStatement = NULL;
    if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) == SQLITE_OK)
    {
        sqlite3_bind_text(sqlStatement, 1, [KEYID UTF8String], -1, SQLITE_TRANSIENT);
        
        while (sqlite3_step(sqlStatement)==SQLITE_ROW) {
            
            if(sqlite3_column_type(sqlStatement, 0) == SQLITE_BLOB
               && sqlite3_column_bytes(sqlStatement, 0) > 0
               && sqlite3_column_type(sqlStatement, 1) == SQLITE_TEXT
               && sqlite3_column_type(sqlStatement, 3) == SQLITE_BLOB
               && sqlite3_column_bytes(sqlStatement, 3) > 0)
            {
                MsgEntry *amsg = [[MsgEntry alloc]init];
                int id_len = sqlite3_column_bytes(sqlStatement, 0);
                amsg.msgid = [NSData dataWithBytes:sqlite3_column_blob(sqlStatement, 0) length:id_len];
                amsg.cTime = amsg.rTime = [NSString stringWithUTF8String:(char *)sqlite3_column_text(sqlStatement, 1)];
                amsg.dir = FromMsg;
                amsg.keyid = KEYID;
                int cipher_len = sqlite3_column_bytes(sqlStatement, 3);
                char* output = (char*)sqlite3_column_blob(sqlStatement, 3);
                amsg.msgbody = [NSData dataWithBytes:output length:cipher_len];
                amsg.smsg = amsg.sfile = Encrypted;
                [tmparray addObject:amsg];
                rownum++;
            }
        }
        sqlite3_finalize(sqlStatement);
    }
    
    return tmparray;
}

- (NSArray *)getEncryptedMessages {
    
	if(!db) {
		[ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
		return nil;
	}
	
	NSMutableArray *tmparray = [NSMutableArray new];
	
	const char *sql = "SELECT * FROM ciphertable WHERE cipher IS NOT NULL ORDER BY cTime ASC";
    sqlite3_stmt *sqlStatement = NULL;
    if(sqlite3_prepare(db, sql, -1, &sqlStatement, NULL) == SQLITE_OK) {
        
        while (sqlite3_step(sqlStatement) == SQLITE_ROW) {
            
            if(sqlite3_column_type(sqlStatement, 0) == SQLITE_BLOB
               && sqlite3_column_bytes(sqlStatement, 0) > 0
               && sqlite3_column_type(sqlStatement, 1) == SQLITE_TEXT
               && sqlite3_column_type(sqlStatement, 2) == SQLITE_TEXT
               && sqlite3_column_type(sqlStatement, 3) == SQLITE_BLOB
               && sqlite3_column_bytes(sqlStatement, 3) > 0
               )
            {
                MsgEntry *amsg = [[MsgEntry alloc]init];
                amsg.msgid = [NSData dataWithBytes:sqlite3_column_blob(sqlStatement, 0) length:sqlite3_column_bytes(sqlStatement, 0)];
                amsg.cTime = amsg.rTime = [NSString stringWithUTF8String:(char *)sqlite3_column_text(sqlStatement, 1)];
                amsg.keyid = [NSString stringWithUTF8String:(char *)sqlite3_column_text(sqlStatement, 2)];
                amsg.msgbody = [NSData dataWithBytes:sqlite3_column_blob(sqlStatement, 3) length:sqlite3_column_bytes(sqlStatement, 3)];
                amsg.smsg = amsg.sfile = Encrypted;
                amsg.dir = FromMsg;
                [tmparray addObject:amsg];
            }
        } // end of while
        sqlite3_finalize(sqlStatement);
    }
    
    return tmparray;
}

- (BOOL)DeleteThread: (NSString*)keyid
{
    if(!db || !keyid){
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
        return NO;
    }
	
    BOOL ret = NO;
    sqlite3_stmt *sqlStatement = NULL;
    const char *sql = "DELETE FROM ciphertable WHERE keyid=?";
		
    if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) == SQLITE_OK){
        // bind msgid
        sqlite3_bind_text (sqlStatement, 1, [keyid UTF8String], -1, SQLITE_TRANSIENT);
        int error = sqlite3_step(sqlStatement);
        if(error!=SQLITE_DONE)
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat:@"Error while creating statement. '%s'", sqlite3_errstr(error)]];
        else
            ret = YES;
        sqlite3_finalize(sqlStatement);
    }
    return ret;
}

- (BOOL) CloseDB
{
    if(!db)
        return YES;
    
    int error = sqlite3_close_v2(db);
	if(error!=SQLITE_OK)
    {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: Unable to close the database: %s", sqlite3_errstr(error)]];
        DEBUGMSG(@"ERROR: Unable to close the database: %s", sqlite3_errstr(error));
        return NO;
    }
    return YES;
}

@end
