-- SQL Server Script
USE Library_Management_System;

--Create ITEM_TYPE table
CREATE TABLE ITEM_TYPE (
    ItemTypeID INT PRIMARY KEY,
    TypeName VARCHAR(100) NOT NULL,
    LoanPeriod INT NOT NULL
);

--Create ITEM table
CREATE TABLE ITEM (
    ItemID INT PRIMARY KEY,
    Title VARCHAR(255) NOT NULL,
    Author VARCHAR(255),
    ISBN VARCHAR(20) UNIQUE,
    ISSN VARCHAR(20),
    Volume INT,
    Issue INT,
    Format VARCHAR(50),
    Size VARCHAR(50),
    ItemTypeID INT NOT NULL,
    FOREIGN KEY (ItemTypeID) REFERENCES ITEM_TYPE(ItemTypeID)
);

--Create COPY table
CREATE TABLE COPY (
    CopyID INT PRIMARY KEY,
    Condition VARCHAR(50) NOT NULL,
    Location VARCHAR(100) NOT NULL,
    ItemID INT NOT NULL,
    FOREIGN KEY (ItemID) REFERENCES ITEM(ItemID)
);

--Create L_USER table (Library User)
CREATE TABLE Lib_USER (
    UserID INT PRIMARY KEY,
    Name VARCHAR(255) NOT NULL,
    Email VARCHAR(100) UNIQUE NOT NULL,
    PhoneNumber VARCHAR(15),
    Role VARCHAR(50) NOT NULL
);

--Create BORROW table
CREATE TABLE BORROW (
    BorrowID INT PRIMARY KEY,
    UserID INT NOT NULL,
    CopyID INT NOT NULL,
    BorrowDate DATE NOT NULL,
    ReturnDate DATE,
    FOREIGN KEY (UserID) REFERENCES Lib_USER(UserID),
    FOREIGN KEY (CopyID) REFERENCES COPY(CopyID)
);

--Create RESERVE table
CREATE TABLE RESERVE (
    ReserveID INT PRIMARY KEY,
    UserID INT NOT NULL,
    CopyID INT NOT NULL,
    ReserveDate DATE NOT NULL,
    FOREIGN KEY (UserID) REFERENCES Lib_USER(UserID),
    FOREIGN KEY (CopyID) REFERENCES COPY(CopyID)
);

--Create FINE table
CREATE TABLE FINE (
    FineID INT PRIMARY KEY,
    BorrowID INT NOT NULL,
    FineAmount DECIMAL(10, 2) NOT NULL,
    FineDate DATE NOT NULL,
    FOREIGN KEY (BorrowID) REFERENCES BORROW(BorrowID)
);

--Create L_TRANSACTION table (Library transaction)
CREATE TABLE L_TRANSACTION (
    TransactionID INT PRIMARY KEY,
    TransactionType VARCHAR(100) NOT NULL,
    TransactionDate DATE NOT NULL,
    FineID INT NOT NULL,
    FOREIGN KEY (FineID) REFERENCES FINE(FineID)
);

GO

--Creating VIEWS
CREATE VIEW MemberBorrowedItems AS
SELECT 
    u.UserID, 
    u.Name AS MemberName, 
    i.Title AS ItemTitle, 
    b.BorrowDate, 
    b.ReturnDate
FROM 
    Lib_USER u
JOIN BORROW b ON u.UserID = b.UserID
JOIN COPY c ON b.CopyID = c.CopyID
JOIN ITEM i ON c.ItemID = i.ItemID
WHERE 
    u.Role IN ('Student', 'Faculty', 'Staff');

GO

CREATE VIEW BorrowedItemsSummary AS
SELECT 
    u.UserID,
    u.Name AS MemberName,
    u.Email AS MemberEmail,
    i.Title AS ItemTitle,
    b.BorrowDate,
    b.ReturnDate,
    COALESCE(f.FineAmount, 0) AS FineAmount
FROM 
    Lib_USER u
JOIN 
    BORROW b ON u.UserID = b.UserID
JOIN 
    COPY c ON b.CopyID = c.CopyID
JOIN 
    ITEM i ON c.ItemID = i.ItemID
LEFT JOIN 
    FINE f ON b.BorrowID = f.BorrowID
WHERE 
    b.ReturnDate IS NULL; -- This filters to only show currently borrowed items
GO


--Creating Triggers
CREATE TRIGGER CheckBorrowLimit
ON BORROW
AFTER INSERT
AS
BEGIN
    DECLARE @UserID INT;
    DECLARE @BorrowCount INT;

    -- Get the UserID from the inserted row
    SELECT @UserID = i.UserID FROM inserted i;

    -- Count how many items the user has currently borrowed
    SELECT @BorrowCount = COUNT(*) 
    FROM BORROW 
    WHERE UserID = @UserID AND ReturnDate IS NULL;

    -- Check if the limit exceeds 5
    IF @BorrowCount > 5
    BEGIN
        -- Rollback the transaction if the limit is exceeded
        ROLLBACK TRANSACTION;
        RAISERROR('Cannot borrow more than 5 items at a time.', 16, 1);		--represent the severity level and state respectively
    END
END;

GO

CREATE TRIGGER AutoApplyFine
ON BORROW
AFTER UPDATE
AS
BEGIN
    DECLARE @BorrowID INT, @ReturnDate DATE, @LoanPeriod INT, @BorrowDate DATE, @DueDate DATE, @OverdueDays INT;

    -- Get BorrowID and ReturnDate from the updated row
    SELECT @BorrowID = BorrowID, @ReturnDate = ReturnDate FROM inserted;

    -- Get the LoanPeriod and BorrowDate for the borrowed item
    SELECT @LoanPeriod = it.LoanPeriod, @BorrowDate = b.BorrowDate
    FROM BORROW b
    JOIN COPY c ON b.CopyID = c.CopyID
    JOIN ITEM i ON c.ItemID = i.ItemID
    JOIN ITEM_TYPE it ON i.ItemTypeID = it.ItemTypeID
    WHERE b.BorrowID = @BorrowID;

    -- Calculate the due date
    SET @DueDate = DATEADD(DAY, @LoanPeriod, @BorrowDate);

    -- Calculate overdue days (only if ReturnDate exists)
    IF @ReturnDate IS NOT NULL
    BEGIN
        SET @OverdueDays = DATEDIFF(DAY, @DueDate, @ReturnDate);

        -- If overdue, apply the fine (assuming $1 per day)
        IF @OverdueDays > 0
        BEGIN
            INSERT INTO FINE (BorrowID, FineAmount, FineDate)
            VALUES (@BorrowID, @OverdueDays * 1, GETDATE());
        END
    END
END;

GO

--Entry of sample data
--Sample Data for ITEM_TYPE
INSERT INTO ITEM_TYPE (ItemTypeID, TypeName, LoanPeriod) VALUES
(1, 'Book', 14),
(2, 'Journal', 7),
(3, 'Digital Media', 30);

--Sample Data for ITEM
INSERT INTO ITEM (ItemID, Title, Author, ISBN, ItemTypeID) VALUES
(1, 'The Great Gatsby', 'F. Scott Fitzgerald', '9780743273565', 1),
(2, 'Nature Journal', NULL, '00280836', 2),
(3, 'Introduction to Algorithms', 'Cormen et al.', '9780262033848', 1);

-- Index on ItemTypeID for faster joins with ITEM_TYPE
CREATE INDEX IDX_Item_ItemTypeID ON ITEM (ItemTypeID);
-- Index on ISBN for faster searches on ISBN
CREATE INDEX IDX_Item_ISBN ON ITEM (ISBN);
-- Index on ISSN for faster searches on ISSN
CREATE INDEX IDX_Item_ISSN ON ITEM (ISSN);

--Sample Data for COPY
INSERT INTO COPY (CopyID, Condition, Location, ItemID) VALUES
(1, 'Good', 'Shelf A1', 1),
(2, 'Good', 'Shelf B2', 2),
(3, 'Fair', 'Shelf C3', 3);

-- Index on ItemID for faster joins with ITEM
CREATE INDEX IDX_Copy_ItemID ON COPY (ItemID);

--Sample Data for Lib_USER
INSERT INTO Lib_USER (UserID, Name, Email, PhoneNumber, Role) VALUES
(1, 'Alice Smith', 'alice.smith@university.edu', '123-456-7890', 'Student'),
(2, 'Bob Johnson', 'bob.johnson@university.edu', '098-765-4321', 'Faculty'),
(3, 'Carol Davis', 'carol.davis@university.edu', '555-555-5555', 'Staff');

-- Index on Email for faster searches on Email
CREATE INDEX IDX_LibUser_Email ON Lib_USER (Email);
-- Index on Role for filtering roles
CREATE INDEX IDX_LibUser_Role ON Lib_USER (Role);

--Sample Data for BORROW
INSERT INTO BORROW (BorrowID, UserID, CopyID, BorrowDate, ReturnDate) VALUES
(1, 1, 1, '2024-09-01', '2024-09-15'),
(2, 2, 3, '2024-09-05', NULL);

-- Index on UserID for faster joins and searches by UserID
CREATE INDEX IDX_Borrow_UserID ON BORROW (UserID);
-- Index on CopyID for faster joins and searches by CopyID
CREATE INDEX IDX_Borrow_CopyID ON BORROW (CopyID);
-- Index on ReturnDate for filtering current borrowed items
CREATE INDEX IDX_Borrow_ReturnDate ON BORROW (ReturnDate);

--Sample Data for RESERVE
INSERT INTO RESERVE (ReserveID, UserID, CopyID, ReserveDate) VALUES
(1, 3, 3, '2024-09-10');

-- Index on UserID for faster joins and searches by UserID
CREATE INDEX IDX_Reserve_UserID ON RESERVE (UserID);
-- Index on CopyID for faster joins and searches by CopyID
CREATE INDEX IDX_Reserve_CopyID ON RESERVE (CopyID);

-- Sample Data for FINE with unique records
INSERT INTO FINE (FineID, BorrowID, FineAmount, FineDate) VALUES
(1, 2, 10.00, '2024-09-01'),  -- Existing fine
(2, 1, 5.00, '2024-09-10'),   -- New fine for BorrowID 1
(3, 2, 15.00, '2024-09-20');   -- New fine for BorrowID 2

-- Index on BorrowID for faster joins with BORROW
CREATE INDEX IDX_Fine_BorrowID ON FINE (BorrowID);

-- Sample Data for L_TRANSACTION
INSERT INTO L_TRANSACTION (TransactionID, TransactionType, TransactionDate, FineID) VALUES
(1, 'Payment', '2024-09-15', 1),  -- Payment for the fine with FineID 1
(2, 'Payment', '2024-09-20', 2),  -- Payment for the fine with FineID 2
(3, 'Waiver', '2024-09-22', 1),   -- Waiver for the fine with FineID 1
(4, 'Payment', '2024-10-01', 3);  -- Payment for the fine with FineID 3

CREATE INDEX IDX_LTransaction_FineID ON L_TRANSACTION (FineID);

GO

CREATE PROCEDURE GetBorrowedItemsByMember
    @UserID INT,        -- Member's ID (input)
    @StartDate DATE,    -- Start of the date range (input)
    @EndDate DATE       -- End of the date range (input)
AS
BEGIN
    -- SQL logic to get borrowed items
    SELECT 
        i.Title,        -- Title of the item
        b.BorrowDate,   -- When it was borrowed
        b.ReturnDate    -- When it was returned (if returned)
    FROM 
        BORROW b
    JOIN 
        COPY c ON b.CopyID = c.CopyID
    JOIN 
        ITEM i ON c.ItemID = i.ItemID
    WHERE 
        b.UserID = @UserID                -- Filter by the given user
        AND b.BorrowDate BETWEEN @StartDate AND @EndDate  -- Filter by date range
    ORDER BY 
        b.BorrowDate;
END;
GO


GO

--Create stored procedure for retrieving outstanding fines by a member
CREATE PROCEDURE GetOutstandingFinesByMember
    @UserID INT  -- Member's ID (input)
AS
BEGIN
    -- SQL logic to get outstanding fines
    SELECT 
        f.FineID,                -- Fine ID
        i.Title,                 -- Title of the item borrowed
        b.BorrowDate,            -- When the item was borrowed
        f.FineAmount,            -- Fine amount
        f.FineDate,              -- Fine issued date
        CASE 
            WHEN lt.TransactionType = 'Payment' THEN 'Paid'  -- If paid
            ELSE 'Outstanding'                               -- If not paid
        END AS FineStatus       -- Check if fine is paid or outstanding
    FROM 
        FINE f
    JOIN 
        BORROW b ON f.BorrowID = b.BorrowID
    JOIN 
        COPY c ON b.CopyID = c.CopyID
    JOIN 
        ITEM i ON c.ItemID = i.ItemID
    LEFT JOIN 
        L_TRANSACTION lt ON f.FineID = lt.FineID  -- Check transactions for payments
    WHERE 
        b.UserID = @UserID  -- Filter by the given user
        AND (lt.TransactionType IS NULL OR lt.TransactionType != 'Payment')  -- Only show outstanding fines
    ORDER BY 
        f.FineDate;
END;
GO



EXEC GetBorrowedItemsByMember @UserID = 1, @StartDate = '2024-01-01', @EndDate = '2024-12-31';

EXEC GetOutstandingFinesByMember @UserID = 1;






--view 
use Library_Management_System;
SELECT * FROM MemberBorrowedItems;
SELECT * FROM BorrowedItemsSummary;

--view trigger
use Library_Management_System;
GO

INSERT INTO BORROW(BorrowID, UserID, CopyID, BorrowDate, ReturnDate)
VALUES (5, 1, 1, '2024-09-12', NULL);

SELECT * FROM BORROW;

--view indexes
select *
from COPY with (INDEX(IDX_Copy_ItemID))

select *
from Lib_USER with (INDEX(IDX_LibUser_Email))

--view procedures
EXEC GetBorrowedItemsByMember @UserID = 1, @StartDate = '2024-01-01', @EndDate = '2024-12-31';
EXEC GetOutstandingFinesByMember @UserID = 1;












